/// Saludo calculado desde la hora LOCAL del dispositivo que muestra el panel.
/// 05:00-12:00 días; 12:01-18:00 tardes; 18:01-04:59 noches.
String dashboardGreeting24N27(DateTime localTime, String userName) {
  final minuteOfDay = localTime.hour * 60 + localTime.minute;
  final String greeting;
  if (minuteOfDay >= 5 * 60 && minuteOfDay <= 12 * 60) {
    greeting = 'Buenos días';
  } else if (minuteOfDay > 12 * 60 && minuteOfDay <= 18 * 60) {
    greeting = 'Buenas tardes';
  } else {
    greeting = 'Buenas noches';
  }
  final name = userName.trim();
  return name.isEmpty ? greeting : '$greeting, $name';
}
