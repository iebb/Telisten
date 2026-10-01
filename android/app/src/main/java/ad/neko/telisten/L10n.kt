package ad.neko.telisten

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalContext

private fun stringId(key: String): Int? = when (key) {
    "%s used" -> R.string.l10n_s_used_ea8ce9d
    "1–12 characters. Uses this exact Telegram folder name for this account. Existing folders are not renamed." -> R.string.l10n_1_12_characters_uses_this_exact_telegram_6a9c019
    "Accounts" -> R.string.l10n_accounts_36bae31
    "Add" -> R.string.l10n_add_61cc55a
    "Add TELEGRAM_API_ID and TELEGRAM_API_HASH to ../.env, then rebuild. You can explore the demo now." -> R.string.l10n_add_telegram_api_id_and_telegram_api_has_112d17f
    "Add a search bot" -> R.string.l10n_add_a_search_bot_24843e6
    "Add account" -> R.string.l10n_add_account_98b0ed8
    "Add bot" -> R.string.l10n_add_bot_f3d8867
    "Add vote" -> R.string.l10n_add_vote_ac9453f
    "After query (optional)" -> R.string.l10n_after_query_optional_8798de4
    "Already broadcasting" -> R.string.l10n_already_broadcasting_92a5053
    "Audio format changed. Restart Listen Together for this track." -> R.string.l10n_audio_format_changed_restart_listen_toge_aa6cf3a
    "Audio service is connecting. Please try again." -> R.string.l10n_audio_service_is_connecting_please_try_a_fd6e5bb
    "Audio service is unavailable" -> R.string.l10n_audio_service_is_unavailable_e8ca884
    "Back to library" -> R.string.l10n_back_to_library_f0926a5
    "Before query (optional)" -> R.string.l10n_before_query_optional_88b769f
    "Broadcast connection failed" -> R.string.l10n_broadcast_connection_failed_2dece2a
    "Broadcast could not keep up. Stop and retry." -> R.string.l10n_broadcast_could_not_keep_up_stop_and_ret_6c01762
    "Broadcast disconnected" -> R.string.l10n_broadcast_disconnected_b424860
    "Broadcast stopped" -> R.string.l10n_broadcast_stopped_4f217ce
    "Browse your chats, play music, and save songs offline." -> R.string.l10n_browse_your_chats_play_music_and_save_so_a636226
    "Cancel" -> R.string.l10n_cancel_77dfd21
    "Channel" -> R.string.l10n_channel_879f0b1
    "Chat" -> R.string.l10n_chat_2ced57f
    "Chats" -> R.string.l10n_chats_6c9e84c
    "Chats could not load" -> R.string.l10n_chats_could_not_load_7597e6d
    "Choose a chat to share the moment." -> R.string.l10n_choose_a_chat_to_share_the_moment_21d374a
    "Clear search" -> R.string.l10n_clear_search_67300d0
    "Comments" -> R.string.l10n_comments_fce06e2
    "Connected" -> R.string.l10n_connected_c2f9b7b
    "Connecting broadcast…" -> R.string.l10n_connecting_broadcast_862bb91
    "Connecting to Telegram" -> R.string.l10n_connecting_to_telegram_c0da91e
    "Connecting…" -> R.string.l10n_connecting_fd3e796
    "Connection interrupted" -> R.string.l10n_connection_interrupted_f8d01ab
    "Connects directly to Telegram. No Telisten server." -> R.string.l10n_connects_directly_to_telegram_no_teliste_9cf4d6b
    "Continue" -> R.string.l10n_continue_2e02623
    "Could not connect" -> R.string.l10n_could_not_connect_9ed243a
    "Could not find the host's song in your music." -> R.string.l10n_could_not_find_the_host_s_song_in_your_m_25b3903
    "Could not join" -> R.string.l10n_could_not_join_4937397
    "Could not save download" -> R.string.l10n_could_not_save_download_88cd019
    "Couldn't finish that" -> R.string.l10n_couldn_t_finish_that_70aa8f3
    "Create a playlist to collect songs from your chats." -> R.string.l10n_create_a_playlist_to_collect_songs_from_efba065
    "Create your Telegram account in the official app, then sign in here." -> R.string.l10n_create_your_telegram_account_in_the_offi_1406b70
    "DEMO" -> R.string.l10n_demo_038bc41
    "Delete" -> R.string.l10n_delete_f6fdbe4
    "Delete %s?" -> R.string.l10n_delete_s_2b61858
    "Delete playlist" -> R.string.l10n_delete_playlist_b55b186
    "Demo" -> R.string.l10n_demo_e52c854
    "Download" -> R.string.l10n_download_a479c9c
    "Download a song from its menu to listen offline." -> R.string.l10n_download_a_song_from_its_menu_to_listen_959da35
    "Download all" -> R.string.l10n_download_all_d69edf7
    "Download interrupted; tap Download to retry." -> R.string.l10n_download_interrupted_tap_download_to_ret_35aa5d3
    "Downloaded" -> R.string.l10n_downloaded_c619702
    "Downloads" -> R.string.l10n_downloads_a862c2b
    "Email address" -> R.string.l10n_email_address_c94d317
    "End session for everyone" -> R.string.l10n_end_session_for_everyone_9ea3044
    "End the current session first." -> R.string.l10n_end_the_current_session_first_0276d05
    "Enter a playlist name" -> R.string.l10n_enter_a_playlist_name_d28e2b6
    "Enter a valid HTTPS lyrics server URL" -> R.string.l10n_enter_a_valid_https_lyrics_server_url_9bde803
    "Enter the code Telegram sent to %s." -> R.string.l10n_enter_the_code_telegram_sent_to_s_13cface
    "Enter the code sent to %s." -> R.string.l10n_enter_the_code_sent_to_s_811aac6
    "Explore demo" -> R.string.l10n_explore_demo_39d369e
    "Favorite %s" -> R.string.l10n_favorite_s_6952fe8
    "Favorites" -> R.string.l10n_favorites_07b3e44
    "Find match" -> R.string.l10n_find_match_8b02192
    "HTTPS server URL" -> R.string.l10n_https_server_url_a8d514a
    "Host here" -> R.string.l10n_host_here_5a9851e
    "Host in a chat you manage, or join a Telisten session. Hosts broadcast app audio to Telegram. Telisten listeners sync matching songs from their own library." -> R.string.l10n_host_in_a_chat_you_manage_or_join_a_teli_b3a6b9c
    "Import LRC" -> R.string.l10n_import_lrc_b16601f
    "In order" -> R.string.l10n_in_order_32a183d
    "In sync with %s" -> R.string.l10n_in_sync_with_s_5bb7736
    "Invite contacts" -> R.string.l10n_invite_contacts_43f0bde
    "Invited %d contacts" -> R.string.l10n_invited_d_contacts_ffea7c3
    "Join session" -> R.string.l10n_join_session_8941a56
    "LRCLIB or your own compatible server" -> R.string.l10n_lrclib_or_your_own_compatible_server_1a1ee9e
    "Leave demo" -> R.string.l10n_leave_demo_4b15613
    "Leave demo?" -> R.string.l10n_leave_demo_3dc5161
    "Leave session" -> R.string.l10n_leave_session_8e22241
    "Library" -> R.string.l10n_library_b8100f5
    "Listen Together needs a signed-in Telegram account." -> R.string.l10n_listen_together_needs_a_signed_in_telegr_d27a273
    "Listen offline" -> R.string.l10n_listen_offline_486cd6f
    "Listen together" -> R.string.l10n_listen_together_7c4268d
    "Live" -> R.string.l10n_live_65c821a
    "Load more" -> R.string.l10n_load_more_dfe60ca
    "Loading music…" -> R.string.l10n_loading_music_c8a22d9
    "Loading…" -> R.string.l10n_loading_33ce417
    "Login email" -> R.string.l10n_login_email_5887f63
    "Lyrics" -> R.string.l10n_lyrics_8670cb1
    "Media controls could not connect: %s" -> R.string.l10n_media_controls_could_not_connect_s_16d9e33
    "Messages are sent through your Telegram account." -> R.string.l10n_messages_are_sent_through_your_telegram_5a02ec7
    "Minimize player" -> R.string.l10n_minimize_player_a5a19fb
    "Move %s down" -> R.string.l10n_move_s_down_eaefe61
    "Move %s up" -> R.string.l10n_move_s_up_79d0fb1
    "Move bot up" -> R.string.l10n_move_bot_up_9cb82d8
    "Move down" -> R.string.l10n_move_down_260ff8a
    "Move up" -> R.string.l10n_move_up_b4f57cd
    "New account" -> R.string.l10n_new_account_d33d781
    "New playlist" -> R.string.l10n_new_playlist_a5474a8
    "Next" -> R.string.l10n_next_bc98198
    "No app can open this link" -> R.string.l10n_no_app_can_open_this_link_0ceb50b
    "No chats found" -> R.string.l10n_no_chats_found_c6bd820
    "No comments yet." -> R.string.l10n_no_comments_yet_207b24f
    "No lyrics found" -> R.string.l10n_no_lyrics_found_75127a1
    "No matching songs" -> R.string.l10n_no_matching_songs_6642d8e
    "No playlists" -> R.string.l10n_no_playlists_d1f610b
    "No songs yet" -> R.string.l10n_no_songs_yet_70cd5c1
    "Now playing" -> R.string.l10n_now_playing_1c388f1
    "OK" -> R.string.l10n_ok_9ce3bd4
    "Offline storage" -> R.string.l10n_offline_storage_c9f2f99
    "Oldest downloaded music is removed when the cache reaches this limit." -> R.string.l10n_oldest_downloaded_music_is_removed_when_0b6b875
    "Open this button in Telegram" -> R.string.l10n_open_this_button_in_telegram_63a9a4e
    "Options for %s" -> R.string.l10n_options_for_s_de37f37
    "Password" -> R.string.l10n_password_8be3c94
    "Pause" -> R.string.l10n_pause_781961b
    "Phone number (+81 …)" -> R.string.l10n_phone_number_81_573327d
    "Play" -> R.string.l10n_play_5d12bd5
    "Play a song before starting a broadcast." -> R.string.l10n_play_a_song_before_starting_a_broadcast_1411680
    "Playlist folder name" -> R.string.l10n_playlist_folder_name_13f2970
    "Playlist is available offline" -> R.string.l10n_playlist_is_available_offline_54b7ee8
    "Playlist name" -> R.string.l10n_playlist_name_544f755
    "Playlists" -> R.string.l10n_playlists_77b69f3
    "Previous" -> R.string.l10n_previous_50f9428
    "Privacy policy" -> R.string.l10n_privacy_policy_7ceacdc
    "Privacy policy & data controls" -> R.string.l10n_privacy_policy_data_controls_33efbf8
    "Private Telegram playlist" -> R.string.l10n_private_telegram_playlist_9593287
    "Queue" -> R.string.l10n_queue_d325fcd
    "Refresh QR code" -> R.string.l10n_refresh_qr_code_0d87d27
    "Remove" -> R.string.l10n_remove_e963907
    "Remove bot" -> R.string.l10n_remove_bot_4812ad0
    "Remove download" -> R.string.l10n_remove_download_1477425
    "Remove from playlist" -> R.string.l10n_remove_from_playlist_ad3e5d8
    "Remove this song?" -> R.string.l10n_remove_this_song_2e0668e
    "Remove vote" -> R.string.l10n_remove_vote_b212f50
    "Rename" -> R.string.l10n_rename_d3f4cb8
    "Rename playlist" -> R.string.l10n_rename_playlist_279af0e
    "Repeat one" -> R.string.l10n_repeat_one_05f3dda
    "Reply on Telegram" -> R.string.l10n_reply_on_telegram_2ab8656
    "Reverse order" -> R.string.l10n_reverse_order_eabc2f7
    "Save" -> R.string.l10n_save_efc007a
    "Save %s" -> R.string.l10n_save_s_3422946
    "Save preferences" -> R.string.l10n_save_preferences_d8ab74e
    "Save to playlist" -> R.string.l10n_save_to_playlist_b97257e
    "Saved" -> R.string.l10n_saved_c0ae8f6
    "Saved in demo" -> R.string.l10n_saved_in_demo_2a23a64
    "Saved to %s" -> R.string.l10n_saved_to_s_1b18781
    "Scan with Telegram" -> R.string.l10n_scan_with_telegram_c387872
    "Search" -> R.string.l10n_search_bce0641
    "Search Telegram or choose a chat to find music." -> R.string.l10n_search_telegram_or_choose_a_chat_to_find_ebea858
    "Search all Telegram" -> R.string.l10n_search_all_telegram_b5b4582
    "Search bots" -> R.string.l10n_search_bots_aeb2b4e
    "Search chats" -> R.string.l10n_search_chats_9ad51de
    "Search for music" -> R.string.l10n_search_for_music_5b96e02
    "Search library" -> R.string.l10n_search_library_1c9edba
    "Search playlists" -> R.string.l10n_search_playlists_756ad7e
    "Search songs and artists" -> R.string.l10n_search_songs_and_artists_c3c2b98
    "Search with a bot" -> R.string.l10n_search_with_a_bot_4f4676b
    "Searches send real messages to this bot." -> R.string.l10n_searches_send_real_messages_to_this_bot_1863c9e
    "Send comment" -> R.string.l10n_send_comment_591e0e8
    "Send search" -> R.string.l10n_send_search_8355677
    "Send searches to bots you choose" -> R.string.l10n_send_searches_to_bots_you_choose_0cc525b
    "Session ended" -> R.string.l10n_session_ended_8874019
    "Settings" -> R.string.l10n_settings_c7f73bb
    "Settings saved" -> R.string.l10n_settings_saved_aef97bb
    "Share invite link" -> R.string.l10n_share_invite_link_a0630b0
    "Share listening session" -> R.string.l10n_share_listening_session_81635bd
    "Show Chats tab" -> R.string.l10n_show_chats_tab_6273f93
    "Shuffle" -> R.string.l10n_shuffle_5b772b7
    "Shuffle all" -> R.string.l10n_shuffle_all_7e388b3
    "Sign in to Telegram" -> R.string.l10n_sign_in_to_telegram_fec2628
    "Sign in with QR code" -> R.string.l10n_sign_in_with_qr_code_ec732c6
    "Sign out of this account" -> R.string.l10n_sign_out_of_this_account_b4e6788
    "Sign out?" -> R.string.l10n_sign_out_b115557
    "Signed out" -> R.string.l10n_signed_out_1b8337c
    "Something went wrong. Please try again." -> R.string.l10n_something_went_wrong_please_try_again_9a3ea05
    "Song title, artist, and duration are sent to this server. Matched lyrics are saved for offline listening." -> R.string.l10n_song_title_artist_and_duration_are_sent_cf70a47
    "Songs" -> R.string.l10n_songs_e1404b4
    "Tap a song's heart to save it here." -> R.string.l10n_tap_a_song_s_heart_to_save_it_here_2b963e6
    "Telegram could not send the message: %s" -> R.string.l10n_telegram_could_not_send_the_message_s_a49a252
    "Telegram did not allow this track to be forwarded." -> R.string.l10n_telegram_did_not_allow_this_track_to_be_3ed619c
    "Telegram error" -> R.string.l10n_telegram_error_6c18eb3
    "Telegram must provide a secure RTMPS endpoint for broadcasting." -> R.string.l10n_telegram_must_provide_a_secure_rtmps_end_f4f3458
    "Telegram rejected the broadcast" -> R.string.l10n_telegram_rejected_the_broadcast_b9113bf
    "Telegram requires a login email address." -> R.string.l10n_telegram_requires_a_login_email_address_2da6b68
    "Telegram sign-in QR code" -> R.string.l10n_telegram_sign_in_qr_code_2fbf268
    "Telegram → Settings → Devices → Link Desktop Device" -> R.string.l10n_telegram_settings_devices_link_desktop_d_d910834
    "Telisten for Android · %s" -> R.string.l10n_telisten_for_android_s_a5374fd
    "Telisten on Telegram" -> R.string.l10n_telisten_on_telegram_b81361a
    "The host ended this session" -> R.string.l10n_the_host_ended_this_session_8b94a82
    "The message will be deleted from this Telegram playlist." -> R.string.l10n_the_message_will_be_deleted_from_this_te_f1d9a28
    "There is no active session in this chat." -> R.string.l10n_there_is_no_active_session_in_this_chat_2fe1fe0
    "This call is not sharing Telisten playback metadata." -> R.string.l10n_this_call_is_not_sharing_telisten_playba_80a3ddf
    "This deletes the playlist channel on Telegram. This cannot be undone." -> R.string.l10n_this_deletes_the_playlist_channel_on_tel_7984b9d
    "This song is not available in your Telegram music. You can listen using the Telegram invite link." -> R.string.l10n_this_song_is_not_available_in_your_teleg_12534df
    "This track exceeds the cache limit. Increase it in Settings." -> R.string.l10n_this_track_exceeds_the_cache_limit_incre_8819ace
    "Toggle favorite" -> R.string.l10n_toggle_favorite_48e9866
    "Try a different name or turn off the saved filter." -> R.string.l10n_try_a_different_name_or_turn_off_the_sav_a72b093
    "Try another match or import an LRC file." -> R.string.l10n_try_another_match_or_import_an_lrc_file_cf73e1a
    "Two-step verification" -> R.string.l10n_two_step_verification_2a0b5e8
    "Unknown artist" -> R.string.l10n_unknown_artist_9566f8c
    "Use _Playlist default" -> R.string.l10n_use_playlist_default_316b1fd
    "Use the phone number connected to Telegram." -> R.string.l10n_use_the_phone_number_connected_to_telegr_6e6c9bb
    "Verification code" -> R.string.l10n_verification_code_80f2f29
    "Vote" -> R.string.l10n_vote_64f8729
    "Your account" -> R.string.l10n_your_account_4ab2910
    "Your downloaded music remains available on this device." -> R.string.l10n_your_downloaded_music_remains_available_808d2df
    "Your two-step verification password" -> R.string.l10n_your_two_step_verification_password_e751dde
    else -> null
}

fun localize(context: Context, key: String, vararg args: Any): String {
    val id = stringId(key) ?: return key
    return if (args.isEmpty()) context.getString(id) else context.getString(id, *args)
}

@Composable
fun tr(key: String, vararg args: Any): String = localize(LocalContext.current, key, *args)

@Composable
fun countLabel(kind: String, count: Int): String {
    val id = when (kind) {
        "playlists" -> R.plurals.l10n_count_playlists
        "chats" -> R.plurals.l10n_count_chats
        "songs" -> R.plurals.l10n_count_songs
        "contacts" -> R.plurals.l10n_count_contacts
        else -> return "$count $kind"
    }
    return LocalContext.current.resources.getQuantityString(id, count, count)
}
