import 'package:breezze_api_client/breezze_api_client.dart';
import 'package:breezze_design_system/breezze_design_system.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/youtube_player_handoff.dart';

import '../../app/bootstrap.dart';
import '../../app/downloads_controller.dart';
import '../../app/search_history_store.dart';
import '../../app/playlist_store.dart';
import '../catalog/catalog_detail_screens.dart';
import '../player/player_controller.dart';
import '../../core/auth/auth_session.dart';
import '../../widgets/bz_brand_icons.dart';

bool _isMetadataOnlySourceTrack(String id) =>
    id.startsWith('bzv:') ||
    (id.startsWith('bz:') && !id.startsWith('bz:audius:'));
