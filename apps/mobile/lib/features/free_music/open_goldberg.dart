/// Kimiko Ishizaka released The Open Goldberg Variations under CC0.
class OpenGoldberg {
  static const artist = 'Kimiko Ishizaka';
  static const album = 'The Open Goldberg Variations';
  static const _collection = 'The_Open_Goldberg_Variations-11823';
  static const _prefix = 'bz:open_goldberg:';
  static const _files = [
    'Kimiko_Ishizaka_-_01_-_Aria.mp3',
    'Kimiko_Ishizaka_-_02_-_Variatio_1_a_1_Clav.mp3',
    'Kimiko_Ishizaka_-_03_-_Variatio_2_a_1_Clav.mp3',
    'Kimiko_Ishizaka_-_04_-_Variatio_3_a_1_Clav_Canone_allUnisuono.mp3',
    'Kimiko_Ishizaka_-_05_-_Variatio_4_a_1_Clav.mp3',
    'Kimiko_Ishizaka_-_06_-_Variatio_5_a_1_ovvero_2_Clav.mp3',
    'Kimiko_Ishizaka_-_07_-_Variatio_6_a_1_Clav_Canone_alla_Seconda.mp3',
    'Kimiko_Ishizaka_-_08_-_Variatio_7_a_1_ovvero_2_Clav.mp3',
    'Kimiko_Ishizaka_-_09_-_Variatio_8_a_2_Clav.mp3',
    'Kimiko_Ishizaka_-_10_-_Variatio_9_a_1_Clav_Canone_alla_Terza.mp3',
    'Kimiko_Ishizaka_-_11_-_Variatio_10_a_1_Clav_Fughetta.mp3',
    'Kimiko_Ishizaka_-_12_-_Variatio_11_a_2_Clav.mp3',
    'Kimiko_Ishizaka_-_13_-_Variatio_12_Canone_alla_Quarta.mp3',
    'Kimiko_Ishizaka_-_14_-_Variatio_13_a_2_Clav.mp3',
    'Kimiko_Ishizaka_-_15_-_Variatio_14_a_2_Clav.mp3',
    'Kimiko_Ishizaka_-_16_-_Variatio_15_a_1_Clav_Canone_alla_Quinta.mp3',
    'Kimiko_Ishizaka_-_17_-_Variatio_16_a_1_Clav_Ouverture.mp3',
    'Kimiko_Ishizaka_-_18_-_Variatio_17_a_2_Clav.mp3',
    'Kimiko_Ishizaka_-_19_-_Variatio_18_a_1_Clav_Canone_alla_Sexta.mp3',
    'Kimiko_Ishizaka_-_20_-_Variatio_19_a_1_Clav.mp3',
    'Kimiko_Ishizaka_-_21_-_Variatio_20_a_2_Clav.mp3',
    'Kimiko_Ishizaka_-_22_-_Variatio_21_Canone_alla_Settima.mp3',
    'Kimiko_Ishizaka_-_23_-_Variatio_22_a_1_Clav.mp3',
    'Kimiko_Ishizaka_-_24_-_Variatio_23_a_2_Clav.mp3',
    'Kimiko_Ishizaka_-_25_-_Variatio_24_a_1_Clav_Canone_allOttava.mp3',
    'Kimiko_Ishizaka_-_26_-_Variatio_25_a_2_Clav.mp3',
    'Kimiko_Ishizaka_-_27_-_Variatio_26_a_2_Clav.mp3',
    'Kimiko_Ishizaka_-_28_-_Variatio_27_a_2_Clav_Canone_alla_Nona.mp3',
    'Kimiko_Ishizaka_-_29_-_Variatio_28_a_2_Clav.mp3',
    'Kimiko_Ishizaka_-_30_-_Variatio_29_a_1_ovvero_2_Clav.mp3',
    'Kimiko_Ishizaka_-_31_-_Variatio_30_a_1_Clav_Quodlibet.mp3',
    'Kimiko_Ishizaka_-_32_-_Aria_da_Capo__Fine.mp3',
  ];

  static int get length => _files.length;
  static String id(int index) => '$_prefix${index + 1}';
  static String title(int index) => _files[index]
      .split('_-_').last.replaceFirst(RegExp(r'\.mp3$'), '')
      .replaceAll(RegExp(r'_+'), ' ');

  static Uri? audio(String trackId) {
    if (!trackId.startsWith(_prefix)) return null;
    final number = int.tryParse(trackId.substring(_prefix.length));
    if (number == null || number < 1 || number > length || trackId != id(number - 1)) return null;
    return Uri.https('archive.org', '/download/$_collection/${_files[number - 1]}');
  }
}
