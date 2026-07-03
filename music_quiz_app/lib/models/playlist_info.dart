/// Sammanfattande info om en spellista, för väljaren (inte själva låtarna).
class PlaylistInfo {
  final String id;
  final String name;
  final String? imageUrl;
  final int trackCount;
  final String ownerName;

  const PlaylistInfo({
    required this.id,
    required this.name,
    this.imageUrl,
    this.trackCount = 0,
    this.ownerName = '',
  });
}
