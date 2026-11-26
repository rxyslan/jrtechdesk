mod file;

use super::{
    get_custom_client_staging_dir, get_reg_of_hkcr, handle_custom_client_staging_dir_before_update,
    installer_files::ProtectedInstallFile,
    installer_handoff::{run_cmds, InstallCommands},
    installer_shell::path_for_cmd_environment,
    remove_custom_client_staging_dir, ResultType, REG_NAME_INSTALL_PRINTER,
};
use hbb_common::{allow_err, anyhow::anyhow, bail, log};
use std::path::{Path, PathBuf};

pub use file::{copy_and_verify_update_file_sha256, VerifiedUpdateFile};

const VERIFIED_UPDATE_FILE_PREFIX: &str = "rustdesk-verified-";
const VERIFIED_EXE_FILENAME: &str = "update.exe";
const VERIFIED_MSI_FILENAME: &str = "update.msi";
const VERIFIED_UPDATE_COPY_FAILURE_EXIT_CODE: u32 = 0x5253_0009;
const VERIFIED_EXE_LAUNCH_FAILURE_EXIT_CODE: u32 = 0x5253_000C;

pub fn update_to_verified(file: &str, expected_sha256: &str, expected_size: u64) -> ResultType<()> {
    let extension = file::update_file_extension(file).unwrap_or_default();
    if extension != "exe" && extension != "msi" {
        bail!("Unsupported update file format: {}", file);
    }

    let update_file = copy_and_verify_update_file_sha256(file, expected_sha256)?;
    if let Err(err) = update_file.verify_size(expected_size) {
        update_file.cleanup();
        return Err(err);
    }
    let update_path = match update_file.path_str() {
        Ok(path) => path.to_owned(),
        Err(err) => {
            update_file.cleanup();
            return Err(err);
        }
    };
    let custom_client_staging_dir = get_custom_client_staging_dir();
    if crate::is_custom_client() {
        if let Err(err) = handle_custom_client_staging_dir_before_update(&custom_client_staging_dir)
        {
            update_file.cleanup();
            return Err(err);
        }
    } else {
        // Clean up any residual staging directory from previous custom client.
        allow_err!(remove_custom_client_staging_dir(&custom_client_staging_dir));
    }

    let result = launch_verified_update(&extension, &update_path, expected_sha256);
    clear_custom_client_staging_after_launch_failure(&custom_client_staging_dir, &result);
    update_file.cleanup();
    result
}

// Definidos pelo packer portátil (libs/portable/src/main.rs); manter os nomes iguais.
const JRTECH_PORTABLE_EXE_ENV_KEY: &str = "JRTECH_PORTABLE_EXE";
const JRTECH_UPDATE_WAIT_PID_ENV_KEY: &str = "JRTECH_UPDATE_WAIT_PID";

/// JrTechDesk suporte (portátil, sem instalação): troca o próprio .exe pela versão
/// nova, já conferida, e abre a versão nova. Quem chama fecha este processo em seguida;
/// o packer novo espera ele sair antes de extrair.
pub fn update_portable_to_verified(
    file: &str,
    expected_sha256: &str,
    expected_size: u64,
) -> ResultType<()> {
    let target = std::env::var_os(JRTECH_PORTABLE_EXE_ENV_KEY)
        .map(PathBuf::from)
        .ok_or_else(|| anyhow!("caminho do JrTechDesk portátil desconhecido"))?;
    let is_exe = target
        .extension()
        .and_then(|e| e.to_str())
        .is_some_and(|e| e.eq_ignore_ascii_case("exe"));
    if !target.is_absolute() || !is_exe || !target.is_file() {
        bail!("caminho do JrTechDesk portátil inválido: {}", target.display());
    }

    // A cópia conferida fica aberta (só leitura compartilhada) até o fim da troca.
    let update_file = copy_and_verify_update_file_sha256(file, expected_sha256)?;
    let result = update_file
        .verify_size(expected_size)
        .and_then(|_| update_file.path_str().map(|p| p.to_owned()))
        .and_then(|new_exe| {
            replace_portable_exe(&target, Path::new(&new_exe), expected_size, expected_sha256)
        });
    update_file.cleanup();
    let old = result?;

    // O packer novo apaga o .old só depois de extrair e abrir; se falhar, ele o restaura.
    if let Err(e) = std::process::Command::new(&target)
        .env(JRTECH_UPDATE_WAIT_PID_ENV_KEY, std::process::id().to_string())
        .spawn()
    {
        restore_portable_exe(&target, &old);
        bail!("falha ao abrir a versão nova {}: {}", target.display(), e);
    }
    Ok(())
}

fn portable_sibling(target: &Path, suffix: &str) -> PathBuf {
    let mut path = target.as_os_str().to_owned();
    path.push(suffix);
    PathBuf::from(path)
}

/// Grava a versão nova ao lado (`.new`), confere o tamanho e só então troca com
/// `ReplaceFileW`, que põe a nova no lugar e guarda a anterior (`.old`) numa operação só
/// do sistema de arquivos. Retorna onde ficou a versão anterior.
fn replace_portable_exe(
    target: &Path,
    new_exe: &Path,
    expected_size: u64,
    expected_sha256: &str,
) -> ResultType<PathBuf> {
    let staged = portable_sibling(target, ".new");
    let old = portable_sibling(target, ".old");
    if staged.exists() {
        std::fs::remove_file(&staged)
            .map_err(|e| anyhow!("falha ao apagar {}: {}", staged.display(), e))?;
    }
    match std::fs::copy(new_exe, &staged) {
        Ok(copied) if copied == expected_size => {}
        Ok(copied) => {
            allow_err!(std::fs::remove_file(&staged));
            bail!(
                "a versão nova ficou com {} bytes em {}, esperado {}",
                copied,
                staged.display(),
                expected_size
            );
        }
        Err(e) => {
            allow_err!(std::fs::remove_file(&staged));
            bail!("falha ao gravar a versão nova em {}: {}", staged.display(), e);
        }
    }
    // A cópia ao lado é a que vai ser executada: grava no disco e confere o SHA-256 de novo,
    // com o arquivo aberto sem permitir escrita de outros processos.
    if let Err(e) = sync_and_verify_staged(&staged, expected_sha256) {
        allow_err!(std::fs::remove_file(&staged));
        return Err(e);
    }
    if old.exists() {
        if let Err(e) = std::fs::remove_file(&old) {
            allow_err!(std::fs::remove_file(&staged));
            bail!("falha ao apagar a cópia antiga {}: {}", old.display(), e);
        }
    }
    // O .exe do packer não está em uso (ele só extrai e abre o app), então dá para trocar.
    if let Err(e) = swap_portable_exe(target, &staged, &old) {
        // Conforme o ponto em que falhou, a anterior pode ter ficado só como .old.
        if !target.exists() && old.exists() {
            restore_portable_exe(target, &old);
        }
        allow_err!(std::fs::remove_file(&staged));
        bail!("falha ao pôr a versão nova em {}: {}", target.display(), e);
    }
    Ok(old)
}

fn sync_and_verify_staged(staged: &Path, expected_sha256: &str) -> ResultType<()> {
    use std::os::windows::fs::OpenOptionsExt;
    use windows::Win32::Storage::FileSystem::{FILE_SHARE_DELETE, FILE_SHARE_READ};

    std::fs::OpenOptions::new()
        .write(true)
        .open(staged)
        .and_then(|file| file.sync_all())
        .map_err(|e| anyhow!("falha ao gravar {} no disco: {}", staged.display(), e))?;
    let mut file = std::fs::OpenOptions::new()
        .read(true)
        .share_mode(FILE_SHARE_READ.0 | FILE_SHARE_DELETE.0)
        .open(staged)
        .map_err(|e| anyhow!("falha ao abrir {}: {}", staged.display(), e))?;
    crate::update_hash::verify_sha256_reader(&mut file, expected_sha256)
        .map_err(|e| anyhow!("a cópia {} não confere: {:?}", staged.display(), e))
}

fn swap_portable_exe(target: &Path, staged: &Path, old: &Path) -> ResultType<()> {
    use windows::{
        core::HSTRING,
        Win32::Storage::FileSystem::{ReplaceFileW, REPLACE_FILE_FLAGS},
    };

    unsafe {
        ReplaceFileW(
            &HSTRING::from(target),
            &HSTRING::from(staged),
            &HSTRING::from(old),
            REPLACE_FILE_FLAGS(0),
            None,
            None,
        )
    }
    .map_err(|err| anyhow!("{}", err))
}

fn restore_portable_exe(target: &Path, old: &Path) {
    if target.exists() {
        allow_err!(std::fs::remove_file(target));
    }
    if let Err(e) = std::fs::rename(old, target) {
        log::warn!(
            "Falha ao restaurar {} a partir de {}: {}",
            target.display(),
            old.display(),
            e
        );
    }
}

fn launch_verified_update(
    extension: &str,
    update_path: &str,
    expected_sha256: &str,
) -> ResultType<()> {
    match extension {
        "exe" => {
            if let Err(err) = launch_verified_exe(update_path, expected_sha256) {
                bail!("Failed to run the update exe: {}", err);
            }
        }
        "msi" => {
            if let Err(err) = install_verified_msi(update_path, expected_sha256, false) {
                bail!("Failed to run the update msi: {}", err);
            }
        }
        _ => bail!("Unsupported update file format: {}", update_path),
    }
    Ok(())
}

fn launch_verified_exe(exe: &str, expected_sha256: &str) -> ResultType<()> {
    let update = ProtectedInstallFile::copy_verified(Path::new(exe), expected_sha256)?;
    let source = path_for_cmd_environment(update.path())?;
    let commands = format!(
        "set \"RUSTDESK_VERIFIED_EXE_SOURCE={source}\"\r\n\
         set \"RUSTDESK_VERIFIED_EXE=%RUSTDESK_OUTPUT_DIR%\\{VERIFIED_EXE_FILENAME}\"\r\n\
         copy /B /Y \"%RUSTDESK_VERIFIED_EXE_SOURCE%\" \"%RUSTDESK_VERIFIED_EXE%\" > nul || exit /b {VERIFIED_UPDATE_COPY_FAILURE_EXIT_CODE}\r\n\
         start \"\" /wait \"%RUSTDESK_VERIFIED_EXE%\" --update || exit /b {VERIFIED_EXE_LAUNCH_FAILURE_EXIT_CODE}"
    );
    run_cmds(
        InstallCommands {
            script: commands,
            files: vec![update],
        },
        false,
        "update-exe",
    )
}

fn verified_msi_install_commands(msi: &Path, quiet: bool) -> ResultType<String> {
    use windows::Win32::Foundation::{
        ERROR_SUCCESS, ERROR_SUCCESS_REBOOT_INITIATED, ERROR_SUCCESS_REBOOT_REQUIRED,
    };

    // The input is already verified and protected, including its parent path.
    // Execute the copy from the protected runner to exclude adjacent untrusted files.
    let source = path_for_cmd_environment(msi)?;
    let quiet_args = if quiet { " /qn LAUNCH_TRAY_APP=N" } else { "" };
    let app_name = crate::get_app_name();
    let subkey = format!(".{}", app_name.to_lowercase());
    let printer_installed = get_reg_of_hkcr(&subkey, REG_NAME_INSTALL_PRINTER).as_deref()
        != Some("0")
        && remote_printer::is_rd_printer_installed(&app_name).unwrap_or_else(|err| {
            log::warn!(
                "Failed to check printer installation status: {err}; skipping printer installation"
            );
            false
        });
    let printer_args = if printer_installed {
        ""
    } else {
        " INSTALLPRINTER=0"
    };
    Ok(format!(
        "set \"RUSTDESK_VERIFIED_MSI_SOURCE={source}\"\r\n\
         set \"RUSTDESK_VERIFIED_MSI=%RUSTDESK_OUTPUT_DIR%\\{VERIFIED_MSI_FILENAME}\"\r\n\
         copy /B /Y \"%RUSTDESK_VERIFIED_MSI_SOURCE%\" \"%RUSTDESK_VERIFIED_MSI%\" > nul || exit /b {VERIFIED_UPDATE_COPY_FAILURE_EXIT_CODE}\r\n\
         msiexec.exe /i \"%RUSTDESK_VERIFIED_MSI%\"{quiet_args}{printer_args} REBOOT=ReallySuppress /norestart\r\n\
         set \"RUSTDESK_MSI_EXIT_CODE=%ERRORLEVEL%\"\r\n\
         if \"%RUSTDESK_MSI_EXIT_CODE%\"==\"{reboot_initiated}\" exit /b {success}\r\n\
         if \"%RUSTDESK_MSI_EXIT_CODE%\"==\"{reboot_required}\" exit /b {success}\r\n\
         exit /b %RUSTDESK_MSI_EXIT_CODE%",
        success = ERROR_SUCCESS.0,
        reboot_initiated = ERROR_SUCCESS_REBOOT_INITIATED.0,
        reboot_required = ERROR_SUCCESS_REBOOT_REQUIRED.0,
    ))
}

pub(super) fn install_verified_msi(
    msi: &str,
    expected_sha256: &str,
    quiet: bool,
) -> ResultType<()> {
    let update = ProtectedInstallFile::copy_verified(Path::new(msi), expected_sha256)?;
    run_cmds(
        InstallCommands {
            script: verified_msi_install_commands(update.path(), quiet)?,
            files: vec![update],
        },
        false,
        "update-msi",
    )
}

fn clear_custom_client_staging_after_launch_failure(
    staging_dir: &Path,
    launch_result: &ResultType<()>,
) {
    if launch_result.is_ok() {
        return;
    }
    if let Err(err) = remove_custom_client_staging_dir(staging_dir) {
        log::warn!(
            "Failed to clear custom client staging directory {:?}: {}",
            staging_dir,
            err
        );
    }
}

pub fn schedule_current_verified_update_file_cleanup() -> ResultType<()> {
    let current_exe = std::env::current_exe()?;
    if should_schedule_verified_update_cleanup(&current_exe) {
        schedule_file_removal_on_reboot(&current_exe)?;
    }
    Ok(())
}

fn should_schedule_verified_update_cleanup(path: &Path) -> bool {
    // UAC may run under another account whose TEMP directory differs from the caller's.
    path.file_name()
        .and_then(|name| name.to_str())
        .is_some_and(|name| name.starts_with(VERIFIED_UPDATE_FILE_PREFIX) && name.ends_with(".exe"))
}

fn schedule_file_removal_on_reboot(path: &Path) -> ResultType<()> {
    use windows::{
        core::{HSTRING, PCWSTR},
        Win32::Storage::FileSystem::{MoveFileExW, MOVEFILE_DELAY_UNTIL_REBOOT},
    };

    unsafe {
        MoveFileExW(
            &HSTRING::from(path),
            PCWSTR::null(),
            MOVEFILE_DELAY_UNTIL_REBOOT,
        )
    }
    .map_err(|err| {
        anyhow!(
            "Failed to schedule verified update file cleanup for {}: {}",
            path.display(),
            err
        )
    })?;
    Ok(())
}
