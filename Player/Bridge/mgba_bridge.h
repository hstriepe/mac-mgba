/* A small C API over libmgba for the Swift player.
 * Every call except the config getters/setters must come from the emulation thread. */
#ifndef MGBA_BRIDGE_H
#define MGBA_BRIDGE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct GBPCore GBPCore;

enum GBPPlatform { GBP_PLATFORM_NONE = -1, GBP_PLATFORM_GBA = 0, GBP_PLATFORM_GB = 1 };

/* Hardware a cartridge carries (GBA GPIO devices, GB MBC7 tilt, ...). */
enum GBPHardware {
	GBP_HW_RTC = 1,
	GBP_HW_RUMBLE = 2,
	GBP_HW_LIGHT_SENSOR = 4,
	GBP_HW_GYRO = 8,
	GBP_HW_TILT = 16,
	GBP_HW_CAMERA = 32,
};

/* GBA keys, same bit order as mGBA (A, B, Select, Start, Right, Left, Up, Down, R, L). */
enum GBPKey {
	GBP_KEY_A = 1 << 0,
	GBP_KEY_B = 1 << 1,
	GBP_KEY_SELECT = 1 << 2,
	GBP_KEY_START = 1 << 3,
	GBP_KEY_RIGHT = 1 << 4,
	GBP_KEY_LEFT = 1 << 5,
	GBP_KEY_UP = 1 << 6,
	GBP_KEY_DOWN = 1 << 7,
	GBP_KEY_R = 1 << 8,
	GBP_KEY_L = 1 << 9,
};

/* Creates a core for the ROM and loads the configuration layers:
 * defaultsPath (the app's bundled defaults.ini, may be NULL) below configPath (the user's config.ini, may not exist). */
GBPCore* gbp_create(const char* romPath, const char* defaultsPath, const char* configPath);
void gbp_destroy(GBPCore*);

/* Configuration (mGBA keys, e.g. "gb.model", "frameskip", "volume"). */
const char* gbp_config_get(GBPCore*, const char* key);
void gbp_config_set(GBPCore*, const char* key, const char* value);    /* user layer, saved */
void gbp_config_set_default(GBPCore*, const char* key, const char* value);
void gbp_config_unset(GBPCore*, const char* key);
bool gbp_config_save(GBPCore*);
/* Re-applies the configuration to the running core (call after changing keys). */
void gbp_config_apply(GBPCore*);

/* Loads the ROM and the battery save (created when missing), then resets. */
bool gbp_start(GBPCore*, const char* savePath);
int gbp_platform(GBPCore*);
uint32_t gbp_hardware(GBPCore*);
void gbp_game_title(GBPCore*, char* out, size_t outSize);
void gbp_game_code(GBPCore*, char* out, size_t outSize);

/* Video: 32-bit RGBX pixels (R in the lowest byte), stride gbp_video_stride() pixels. */
void gbp_video_size(GBPCore*, unsigned* width, unsigned* height);
const uint32_t* gbp_video_buffer(GBPCore*);
size_t gbp_video_stride(GBPCore*);

/* Runs one emulated frame. */
void gbp_run_frame(GBPCore*);
double gbp_frame_rate(GBPCore*);

/* Audio: interleaved stereo int16. Returns the number of stereo frames read. */
unsigned gbp_audio_sample_rate(GBPCore*);
size_t gbp_audio_available(GBPCore*);
size_t gbp_audio_read(GBPCore*, int16_t* out, size_t maxFrames);

void gbp_set_keys(GBPCore*, uint32_t keys);
void gbp_reset(GBPCore*);

/* Save states, files in mGBA's own format (compatible with mGBA's .ss0-.ss9). */
bool gbp_state_save(GBPCore*, const char* path);
bool gbp_state_load(GBPCore*, const char* path);

/* Battery save import/export (raw .sav). */
bool gbp_savedata_export(GBPCore*, const char* path);
bool gbp_savedata_import(GBPCore*, const char* path);
/* Switches the battery save to another file (after the save folder changed). */
bool gbp_savedata_reload(GBPCore*, const char* path);

/* Game Boy palette presets (mGBA's list, e.g. "Grayscale", "DMG Green", "Super Game Boy 1-A"). */
size_t gbp_gb_palette_count(void);
const char* gbp_gb_palette_name(size_t index);
void gbp_gb_palette_apply(GBPCore*, size_t index);

/* Rewind (mGBA's rewind buffer). capacity = states kept, interval = frames between states. */
void gbp_rewind_configure(GBPCore*, bool enable, int capacity, int interval);
/* Restores the previous rewind state; run frames with gbp_set_rewinding(true) meanwhile so none are appended. */
bool gbp_rewind_step(GBPCore*);
void gbp_set_rewinding(GBPCore*, bool rewinding);

/* Cheats in mGBA's .cheats format. */
bool gbp_cheats_load(GBPCore*, const char* path);
bool gbp_cheats_save(GBPCore*, const char* path);
size_t gbp_cheats_count(GBPCore*);
void gbp_cheats_name(GBPCore*, size_t index, char* out, size_t outSize);
bool gbp_cheats_enabled(GBPCore*, size_t index);
void gbp_cheats_set_enabled(GBPCore*, size_t index, bool enabled);
void gbp_cheats_remove(GBPCore*, size_t index);
/* Adds a set from one or more code lines (separated by newlines). */
bool gbp_cheats_add(GBPCore*, const char* name, const char* codes);

/* Peripherals. */
void gbp_set_light_level(GBPCore*, int level);    /* 0 (dark) - 10 (bright sun) */
int gbp_light_level(GBPCore*);
void gbp_set_tilt(GBPCore*, float x, float y);    /* -1 ... 1 */
float gbp_rumble_level(GBPCore*);                 /* 0 ... 1 */

#ifdef __cplusplus
}
#endif

#endif
