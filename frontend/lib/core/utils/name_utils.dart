class NameUtils {
  /// Returns the first name (first word) from a full name string.
  /// If the name is empty or null, returns an empty string.
  static String getFirstName(String? fullName) {
    if (fullName == null || fullName.trim().isEmpty) return "";
    return fullName.trim().split(' ').first;
  }
}
