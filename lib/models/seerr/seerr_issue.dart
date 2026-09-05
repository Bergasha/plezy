/// Seerr's fixed issue-type enum (`server/constants/issue.ts`): the
/// underlying wire value is a small integer, not a string.
enum SeerrIssueType {
  video(1),
  audio(2),
  subtitles(3),
  other(4);

  final int wireValue;
  const SeerrIssueType(this.wireValue);
}
