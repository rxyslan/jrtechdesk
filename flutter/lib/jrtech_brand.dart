import 'dart:ui';

// O workflow troca o valor abaixo pelo input "tema" antes de compilar.
const String kJrTechTheme = 'padrao';

const bool _siin = kJrTechTheme == 'siin';

const String kJrTechCredit = 'JrTechDesk - Desenvolvido por Rayslan';

const Color kBrandAccent = _siin ? Color(0xFF01A85A) : Color(0xFF0071FF);
const Color kBrandAccent50 = _siin ? Color(0x7701A85A) : Color(0x770071FF);
const Color kBrandAccent80 = _siin ? Color(0xAA01A85A) : Color(0xAA0071FF);
const Color kBrandButton = _siin ? Color(0xFF01A85A) : Color(0xFF2C8CFF);
const Color kBrandIdColor = _siin ? Color(0xFF01A85A) : Color(0xFF00B6F0);
const Color kBrandAboutBg = _siin ? Color(0xFF00331C) : Color(0xFF2C8CFF);
