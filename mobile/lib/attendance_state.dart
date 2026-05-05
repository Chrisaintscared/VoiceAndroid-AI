/// Shared attendance flow state enum.
/// Import this wherever AttendanceState is needed.
enum AttendanceState {
  idle,
  recording,
  processing,
  success,
  error,
}
