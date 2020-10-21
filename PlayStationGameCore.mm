// Copyright (c) 2020, OpenEmu Team
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//     * Redistributions of source code must retain the above copyright
//       notice, this list of conditions and the following disclaimer.
//     * Redistributions in binary form must reproduce the above copyright
//       notice, this list of conditions and the following disclaimer in the
//       documentation and/or other materials provided with the distribution.
//     * Neither the name of the OpenEmu Team nor the
//       names of its contributors may be used to endorse or promote products
//       derived from this software without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY OpenEmu Team ''AS IS'' AND ANY
// EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
// WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
// DISCLAIMED. IN NO EVENT SHALL OpenEmu Team BE LIABLE FOR ANY
// DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
// (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
// LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
// ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
// SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

#import "PlayStationGameCore.h"
#import "OEPSXSystemResponderClient.h"
#import <OpenEmuBase/OpenEmuBase.h>
#define TickCount DuckTickCount
#include "core/types.h"
#include "core/system.h"
#include "common/log.h"
#include "common/file_system.h"
#include "common/byte_stream.h"
#include "core/host_display.h"
#include "core/host_interface.h"
#include "core/gpu.h"
#include "common/audio_stream.h"
#include "core/digital_controller.h"
#include "core/analog_controller.h"
#include "frontend-common/opengl_host_display.h"
#include "frontend-common/game_settings.h"
#include "core/cheats.h"
Log_SetChannel(OpenEmuHost);
#undef TickCount
#include <limits>
#include <optional>
#include <cstdint>
#include <vector>
#include <string>
#include <memory>

class OpenEmuAudioStream;
class OpenEmuOpenGLHostDisplay;
class OpenEmuHostInterface;

static void updateAnalogAxis(OEPSXButton button, int player, CGFloat amount);
static void updateAnalogControllerButton(OEPSXButton button, int player, bool down);
static void updateDigitalControllerButton(OEPSXButton button, int player, bool down);
// We're keeping this: I think it'll be useful when OpenEmu supports Metal.
static WindowInfo WindowInfoFromGameCore(PlayStationGameCore *core);

class OpenEmuAudioStream final : public AudioStream
{
public:
	OpenEmuAudioStream();
	~OpenEmuAudioStream();

protected:
	bool OpenDevice() override {
		m_output_buffer.resize(m_buffer_size * m_channels);
		return true;
	}
	void PauseDevice(bool paused) override {}
	void CloseDevice() override {}
	void FramesAvailable() override;

private:
	// TODO: Optimize this buffer away.
	std::vector<SampleType> m_output_buffer;
};

class OpenEmuOpenGLHostDisplay final : public FrontendCommon::OpenGLHostDisplay
{
public:
	OpenEmuOpenGLHostDisplay();
	~OpenEmuOpenGLHostDisplay();
	
	RenderAPI GetRenderAPI() const override;
	
	bool CreateRenderDevice(const WindowInfo& wi, std::string_view adapter_name, bool debug_device) override;
	
	void SetVSync(bool enabled) override;
	
	bool Render() override;
};


class OpenEmuHostInterface : public HostInterface
{
public:
	OpenEmuHostInterface();
	~OpenEmuHostInterface() override;
	
	ALWAYS_INLINE u32 GetResolutionScale() const { return g_settings.gpu_resolution_scale; }
	
	bool Initialize() override;
	void Shutdown() override;
	
	void ReportError(const char* message) override;
	void ReportMessage(const char* message) override;
	bool ConfirmMessage(const char* message) override;
	void AddOSDMessage(std::string message, float duration = 2.0f) override;
	
	void GetGameInfo(const char* path, CDImage* image, std::string* code, std::string* title) override;
	std::string GetSharedMemoryCardPath(u32 slot) const override;
	std::string GetGameMemoryCardPath(const char* game_code, u32 slot) const override;
	std::string GetShaderCacheBasePath() const override;
	std::string GetStringSettingValue(const char* section, const char* key, const char* default_value = "") override;
	std::string GetBIOSDirectory() override;
	void ApplyGameSettings(bool display_osd_messages);
	void OnRunningGameChanged() override;
	
	bool LoadCompatibilitySettings(const char* path);
	const GameSettings::Entry* GetGameFixes(const std::string& game_code);

	void ChangeFiltering(GPUTextureFilter new_filter)
	{
		Settings old_settings(std::move(g_settings));
		g_settings.gpu_texture_filter = new_filter;
		CheckForSettingsChanges(old_settings);
	}
	
	void ChangePXGP(bool set_on)
	{
		Settings old_settings(std::move(g_settings));
		g_settings.gpu_pgxp_enable = set_on;
		CheckForSettingsChanges(old_settings);
	}
	
	void Render();
	inline void ResizeRenderWindow(s32 new_window_width, s32 new_window_height)
	{
		if (m_display) {
			m_display->ResizeRenderWindow(new_window_width, new_window_height);
		}
	}

protected:
	bool AcquireHostDisplay() override;
	void ReleaseHostDisplay() override;
	std::unique_ptr<AudioStream> CreateAudioStream(AudioBackend backend) override;
	void LoadSettings() override;
	
private:
	bool CreateDisplay();
	
	bool m_interfaces_initialized = false;
	GameSettings::Database m_game_settings;
};

@interface PlayStationGameCore () <OEPSXSystemResponderClient>

@end




@implementation PlayStationGameCore {
	OpenEmuHostInterface *duckInterface;
    NSString *bootPath;
	NSString *saveStatePath;
    bool isInitialized;
	NSInteger _maxDiscs;
	NSMutableDictionary <NSString *, id> *_displayModes;
}

- (instancetype)init
{
	if (self = [super init]) {
		_current = self;
		Log::SetFilterLevel(LOGLEVEL_TRACE);
		g_settings.gpu_renderer = GPURenderer::HardwareOpenGL;
		g_settings.controller_types[0] = ControllerType::AnalogController;
		g_settings.controller_types[1] = ControllerType::AnalogController;
		g_settings.display_crop_mode = DisplayCropMode::Overscan;
		g_settings.gpu_disable_interlacing = true;
		// match PS2's speed-up
		g_settings.cdrom_read_speedup = 4;
		g_settings.gpu_pgxp_enable = true;
		g_settings.gpu_pgxp_vertex_cache = true;
		g_settings.gpu_texture_filter = GPUTextureFilter::Nearest;
		g_settings.gpu_resolution_scale = 0;
		g_settings.memory_card_types[0] = MemoryCardType::PerGameTitle;
		g_settings.memory_card_types[1] = MemoryCardType::PerGameTitle;
		g_settings.cpu_execution_mode = CPUExecutionMode::Recompiler;
		duckInterface = new OpenEmuHostInterface();
		_displayModes = [[NSMutableDictionary alloc] init];
		_displayModes[@"duckstation/GPU/TextureFilter"] = @0;
		_displayModes[@"duckstation/PXGP"] = @YES;
		NSURL *gameSettingsURL = [[NSBundle bundleForClass:[PlayStationGameCore class]] URLForResource:@"gamesettings" withExtension:@"ini" subdirectory:@"database"];
		if (gameSettingsURL) {
			bool success = duckInterface->LoadCompatibilitySettings(gameSettingsURL.fileSystemRepresentation);
			if (!success) {
				Log_WarningPrintf("Game settings for particular discs didn't load, path %s", gameSettingsURL.fileSystemRepresentation);
			}
		} else {
			Log_WarningPrintf("Game settings for particular discs wasn't found.");
		}
	}
	return self;
}

- (BOOL)loadFileAtPath:(NSString *)path error:(NSError **)error
{
	Log::SetFileOutputParams(true, [self.supportDirectoryPath stringByAppendingPathComponent:@"emu.log"].fileSystemRepresentation);
	if ([[path pathExtension] compare:@"ccd" options:NSCaseInsensitiveSearch] == NSOrderedSame) {
		//DuckStation doens't handle CCD files gracefully. Replace with the likely-present .IMG instead
		path = [[path stringByDeletingPathExtension] stringByAppendingPathExtension:@"img"];
	} else if([path.pathExtension.lowercaseString isEqualToString:@"m3u"]) {
		// Parse number of discs in m3u
		NSString *m3uString = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
		NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@".*\\.cue" /*|.*\\.ccd" ccd disabled for now*/ options:NSRegularExpressionCaseInsensitive error:nil];
		NSUInteger numberOfMatches = [regex numberOfMatchesInString:m3uString options:0 range:NSMakeRange(0, m3uString.length)];
		
		NSLog(@"[DuckStation] Loaded m3u containing %lu cue sheets", numberOfMatches);
		
		_maxDiscs = numberOfMatches;
	}
    bootPath = [path copy];

    return true;
}

- (void)loadStateFromFileAtPath:(NSString *)fileName completionHandler:(void (^)(BOOL, NSError *))block
{
	if (!isInitialized) {
		saveStatePath = [fileName copy];
		block(YES, nil);
		return;
	}
	const bool result = duckInterface->LoadState(fileName.fileSystemRepresentation);
	
	block(result, nil);
}

- (void)saveStateToFileAtPath:(NSString *)fileName completionHandler:(void (^)(BOOL, NSError *))block
{
	std::unique_ptr<ByteStream> stream = FileSystem::OpenFile(fileName.fileSystemRepresentation, BYTESTREAM_OPEN_CREATE | BYTESTREAM_OPEN_WRITE | BYTESTREAM_OPEN_TRUNCATE |
									   BYTESTREAM_OPEN_ATOMIC_UPDATE | BYTESTREAM_OPEN_STREAMED | BYTESTREAM_OPEN_CREATE_PATH);
	if (!stream) {
		block(NO, nil);
		return;
	}

	const bool result = System::SaveState(stream.get());
	
	block(result, nil);
}

static bool IsHexCharacter(char c)
{
	return (c >= 'A' && c <= 'F') || (c >= 'a' && c <= 'f') || (c >= '0' && c <= '9');
}

static bool LoadFromPCSXRString(CheatList &list, NSData* filename)
{
	auto fp = FileSystem::ManagedCFilePtr(fmemopen((void*)filename.bytes, filename.length, "rb"), [](std::FILE* fp) { std::fclose(fp); });
	if (!fp) {
		return false;
	}
	
	char line[1024];
	CheatCode current_code;
	while (std::fgets(line, sizeof(line), fp.get())) {
		char* start = line;
		while (*start != '\0' && std::isspace(*start)) {
			start++;
		}
		
		// skip empty lines
		if (*start == '\0') {
			continue;
		}
		
		char* end = start + std::strlen(start) - 1;
		while (end > start && std::isspace(*end)) {
			*end = '\0';
			end--;
		}
		
		// skip comments and empty line
		if (*start == '#' || *start == ';' || *start == '/' || *start == '\"') {
			continue;
		}
		
		if (*start == '[' && *end == ']') {
			start++;
			*end = '\0';
			
			// new cheat
			if (current_code.Valid()) {
				list.AddCode(current_code);
			}
			
			current_code = {};
			current_code.enabled = false;
			if (*start == '*') {
				current_code.enabled = true;
				start++;
			}
			
			current_code.description.append(start);
			continue;
		}
		
		while (!IsHexCharacter(*start) && start != end) {
			start++;
		}
		if (start == end) {
			continue;
		}
		
		char* end_ptr;
		CheatCode::Instruction inst;
		inst.first = static_cast<u32>(std::strtoul(start, &end_ptr, 16));
		inst.second = 0;
		if (end_ptr) {
			while (!IsHexCharacter(*end_ptr) && end_ptr != end) {
				end_ptr++;
			}
			if (end_ptr != end) {
				inst.second = static_cast<u32>(std::strtoul(end_ptr, nullptr, 16));
			}
		}
		current_code.instructions.push_back(inst);
	}
	
	if (current_code.Valid()) {
		list.AddCode(current_code);
	}
	
	//Log_InfoPrintf("Loaded %zu cheats from '%s' (PCSXR format)", m_codes.size(), filename);
	return list.GetCodeCount() != 0;
}

- (void)setCheat:(NSString *)code setType:(NSString *)type setEnabled:(BOOL)enabled
{
	//TODO: implement better
	auto list = std::make_unique<CheatList>();
	NSData *ourDat = [code dataUsingEncoding:NSUTF8StringEncoding];
	LoadFromPCSXRString(*list.get(), ourDat);
	//list->Apply();
	//System::SetCheatList(std::move(list));
}

- (NSUInteger)discCount
{
	return _maxDiscs ? _maxDiscs : 1;
}

- (void)setDisc:(NSUInteger)discNumber
{
	if (System::HasMediaPlaylist()) {
		uint32_t index = (uint32_t)discNumber - 1; // 0-based index
		System::SwitchMediaFromPlaylist(index);
	}
}

- (void)resetEmulation
{
	duckInterface->ResetSystem();
}

- (void)stopEmulation
{
	duckInterface->Shutdown();
	
	[super stopEmulation];
}

- (OEIntSize)aspectSize
{
	return (OEIntSize){ 4, 3 };
}

- (BOOL)tryToResizeVideoTo:(OEIntSize)size
{
	if (!System::IsShutdown()) {
		duckInterface->ResizeRenderWindow(size.width, size.height);
		
		g_gpu->UpdateResolutionScale();
	}
	return YES;
}

- (OEGameCoreRendering)gameCoreRendering
{
	//TODO: return OEGameCoreRenderingMetal1Video;
	return OEGameCoreRenderingOpenGL3Video;
}

- (oneway void)mouseMovedAtPoint:(OEIntPoint)point
{
	switch (g_settings.controller_types[0]) {
		case ControllerType::NamcoGunCon:
			//TODO: implement
			break;
		default:
			break;
	}
}

- (oneway void)leftMouseDownAtPoint:(OEIntPoint)point
{
	switch (g_settings.controller_types[0]) {
		case ControllerType::NamcoGunCon:
			//TODO: implement
			break;
		default:
			break;
	}
}

- (oneway void)leftMouseUp
{
	switch (g_settings.controller_types[0]) {
		case ControllerType::NamcoGunCon:
			//TODO: implement
			break;
		default:
			break;
	}
}

- (oneway void)rightMouseDownAtPoint:(OEIntPoint)point
{
	switch (g_settings.controller_types[0]) {
		case ControllerType::NamcoGunCon:
			//TODO: implement
			break;
		default:
			break;
	}
}

- (oneway void)rightMouseUp
{
	switch (g_settings.controller_types[0]) {
		case ControllerType::NamcoGunCon:
			//TODO: implement
			break;
		default:
			break;
	}
}

- (oneway void)didMovePSXJoystickDirection:(OEPSXButton)button withValue:(CGFloat)value forPlayer:(NSUInteger)player {
    player -= 1;
    switch (button) {
        case OEPSXLeftAnalogLeft:
        case OEPSXLeftAnalogUp:
        case OEPSXRightAnalogLeft:
        case OEPSXRightAnalogUp:
            value *= -1;
            break;
        default:
            break;
    }
	switch (g_settings.controller_types[player]) {
		case ControllerType::AnalogController:
			updateAnalogAxis(button, (int)player, value);
			break;
			
		default:
			break;
	}
}

- (oneway void)didPushPSXButton:(OEPSXButton)button forPlayer:(NSUInteger)player {
    player -= 1;
    
	switch (g_settings.controller_types[player]) {
		case ControllerType::DigitalController:
			updateDigitalControllerButton(button, (int)player, true);
			break;
			
		case ControllerType::AnalogController:
			updateAnalogControllerButton(button, (int)player, true);
			break;
			
		default:
			break;
	}
}


- (oneway void)didReleasePSXButton:(OEPSXButton)button forPlayer:(NSUInteger)player {
    player -= 1;
    
	switch (g_settings.controller_types[player]) {
		case ControllerType::DigitalController:
			updateDigitalControllerButton(button, (int)player, false);
			break;
			
		case ControllerType::AnalogController:
			updateAnalogControllerButton(button, (int)player, false);
			break;
			
		default:
			break;
	}
}

- (NSUInteger)channelCount
{
	return 2;
}

- (NSUInteger)audioBitDepth
{
	return 16;
}

- (double)audioSampleRate
{
	return 44100;
}

- (OEIntSize)bufferSize
{
	return (OEIntSize){ 640, 480 };
}

- (void)executeFrame
{
    if (!isInitialized){
        SystemBootParameters params(bootPath.fileSystemRepresentation);
        duckInterface->Initialize();
        isInitialized = duckInterface->BootSystem(params);
		if (saveStatePath) {
			duckInterface->LoadState(saveStatePath.fileSystemRepresentation);
			saveStatePath = nil;
		}
    }
    
	System::RunFrame();
	
	duckInterface->Render();
}

- (NSArray <NSDictionary <NSString *, id> *> *)displayModes
{
#define OptionWithValue(n, k, v) \
@{ \
	OEGameCoreDisplayModeNameKey : n, \
	OEGameCoreDisplayModePrefKeyNameKey : k, \
	OEGameCoreDisplayModeStateKey : @([_displayModes[k] isEqual:@(v)]), \
	OEGameCoreDisplayModePrefValueNameKey : @(v) , \
	OEGameCoreDisplayModeIndentationLevelKey : @(1) }
#define OptionToggleWithValue(n, k, v) \
@{ \
	OEGameCoreDisplayModeNameKey : n, \
	OEGameCoreDisplayModePrefKeyNameKey : k, \
	OEGameCoreDisplayModeStateKey : @([_displayModes[k] isEqual:@(v)]), \
	OEGameCoreDisplayModePrefValueNameKey : @(![_displayModes[k] isEqual:@(v)]) }

//	OEDisplayMode_OptionWithStateValue(n, k, @([_displayModes[k] isEqual:@ v]), @#v)
//OEGameCoreDisplayModeIndentationLevelKey : @(1)
	return @[
		@{ OEGameCoreDisplayModeLabelKey : @"Texture Filtering" },
		OptionWithValue(@"Nearest Neighbor", @"duckstation/GPU/TextureFilter", 0),
		OptionWithValue(@"Bilinear", @"duckstation/GPU/TextureFilter", 1),
		OptionWithValue(@"JINC2", @"duckstation/GPU/TextureFilter", 2),
		OptionWithValue(@"xBR", @"duckstation/GPU/TextureFilter", 3),
		@{OEGameCoreDisplayModeSeparatorItemKey : @0},
//		OEDisplayMode_OptionToggleableWithState(@"PXGP", @"duckstation/PXGP", _displayModes[@"duckstation/PXGP"]),
		OptionToggleWithValue(@"PXGP", @"duckstation/PXGP", YES),
//		OEDisplayMode_OptionDefaultWithValue(@"PXGP", @"duckstation/PXGP", @YES)
	];
	
#undef OptionWithValue
}

- (void)changeDisplayWithMode:(NSString *)displayMode
{
	NSString *key;
	id currentVal;
	OEDisplayModeListGetPrefKeyValueFromModeName(self.displayModes, displayMode, &key, &currentVal);
	_displayModes[key] = currentVal;

	if ([key isEqualToString:@"duckstation/GPU/TextureFilter"]) {
		duckInterface->ChangeFiltering(GPUTextureFilter([currentVal intValue]));
	} else if ([key isEqualToString:@"duckstation/PXGP"]) {
		duckInterface->ChangePXGP([currentVal boolValue]);
	}
}

@end

#pragma mark -

#define TickCount DuckTickCount
#include "common/assert.h"
#include "common/log.h"
#include "core/gpu.h"
#include "common/gl/program.h"
#include "common/gl/texture.h"
#include "common/gl/context_agl.h"
#undef TickCount
#include <array>
#include <tuple>

#pragma mark OpenEmuOpenGLHostDisplay methods -

OpenEmuOpenGLHostDisplay::OpenEmuOpenGLHostDisplay()=default;
OpenEmuOpenGLHostDisplay::~OpenEmuOpenGLHostDisplay()=default;

bool OpenEmuOpenGLHostDisplay::CreateRenderDevice(const WindowInfo& wi, std::string_view adapter_name, bool debug_device)
{
	static constexpr std::array<GL::Context::Version, 3> versArray {{{GL::Context::Profile::Core, 4, 1}, {GL::Context::Profile::Core, 3, 3}, {GL::Context::Profile::Core, 3, 2}}};

	m_gl_context = GL::ContextAGL::Create(wi, versArray.data(), versArray.size());
	if (!m_gl_context) {
		Log_ErrorPrintf("Failed to create any GL context");
		return false;
	}

	gladLoadGL();
	m_window_info = wi;
	m_window_info.surface_width = m_gl_context->GetSurfaceWidth();
	m_window_info.surface_height = m_gl_context->GetSurfaceHeight();
	return true;
}

void OpenEmuOpenGLHostDisplay::SetVSync(bool enabled)
{
	_current.renderDelegate.enableVSync = enabled;
}

bool OpenEmuOpenGLHostDisplay::Render() {
	GLuint framebuffer = [[[_current renderDelegate] presentationFramebuffer] unsignedIntValue];

	glDisable(GL_SCISSOR_TEST);
	glBindFramebuffer(GL_DRAW_FRAMEBUFFER, framebuffer);
	glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
	glClear(GL_COLOR_BUFFER_BIT);

	RenderDisplay();

	RenderSoftwareCursor();

	m_gl_context->SwapBuffers();

	return true;
}

FrontendCommon::OpenGLHostDisplay::RenderAPI OpenEmuOpenGLHostDisplay::GetRenderAPI() const {
	return RenderAPI::OpenGL;
}


#pragma mark -

#define TickCount DuckTickCount
#include "common/assert.h"
#include "common/byte_stream.h"
#include "common/file_system.h"
#include "common/log.h"
#include "common/string_util.h"
#include "core/analog_controller.h"
#include "core/bus.h"
#include "core/cheats.h"
#include "core/digital_controller.h"
#include "core/gpu.h"
#include "core/system.h"
#undef TickCount
#include <array>
#include <cstring>
#include <tuple>
#include <utility>
#include <vector>


#pragma mark OpenEmuHostInterface methods -

OpenEmuHostInterface::OpenEmuHostInterface()=default;
OpenEmuHostInterface::~OpenEmuHostInterface()=default;

bool OpenEmuHostInterface::Initialize() {
	m_program_directory = [NSBundle bundleForClass:[PlayStationGameCore class]].resourceURL.fileSystemRepresentation;
	m_user_directory = [_current supportDirectoryPath].fileSystemRepresentation;
	if (!HostInterface::Initialize())
	  return false;

	if (!CreateDisplay()) {
		return false;
	}
	FixIncompatibleSettings(false);
	
	return true;
}

void OpenEmuHostInterface::Shutdown()
{
	HostInterface::Shutdown();
	
}

void OpenEmuHostInterface::Render()
{
	m_display->Render();
}

void OpenEmuHostInterface::ReportError(const char* message)
{
	Log_ErrorPrint(message);
}

void OpenEmuHostInterface::ReportMessage(const char* message)
{
	Log_WarningPrint(message);
}

bool OpenEmuHostInterface::ConfirmMessage(const char* message)
{
	return true;
}

void OpenEmuHostInterface::AddOSDMessage(std::string message, float duration)
{
	Log_InfoPrint(message.c_str());
}

void OpenEmuHostInterface::GetGameInfo(const char* path, CDImage* image, std::string* code, std::string* title)
{
	if (image) {
		*code = System::GetGameCodeForImage(image);
		*title = System::GetGameCodeForImage(image);
	}
}

std::string OpenEmuHostInterface::GetSharedMemoryCardPath(u32 slot) const
{
	NSString *path = _current.batterySavesDirectoryPath;
	if (![[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:NULL]) {
		[[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:NULL];
	}
	return [path stringByAppendingPathComponent:[NSString stringWithFormat:@"Shared Memory Card-%d.mcd", slot]].fileSystemRepresentation;
}

std::string OpenEmuHostInterface::GetGameMemoryCardPath(const char* game_code, u32 slot) const
{
	NSString *path = _current.batterySavesDirectoryPath;
	if (![[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:NULL]) {
		[[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:NULL];
	}
	return [path stringByAppendingPathComponent:[NSString stringWithFormat:@"%s-%d.mcd", game_code, slot]].fileSystemRepresentation;
}

std::string OpenEmuHostInterface::GetShaderCacheBasePath() const
{
	NSString *path = [_current.supportDirectoryPath stringByAppendingPathComponent:@"ShaderCache"];
	if (![[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:NULL]) {
		[[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:NULL];
	}
	return path.fileSystemRepresentation;
}

std::string OpenEmuHostInterface::GetStringSettingValue(const char* section, const char* key, const char* default_value)
{
	return "";
}

std::string OpenEmuHostInterface::GetBIOSDirectory()
{
	return _current.biosDirectoryPath.fileSystemRepresentation;
}

bool OpenEmuHostInterface::AcquireHostDisplay()
{
	if (!m_display) {
		return CreateDisplay();
	}
	return true;
}

void OpenEmuHostInterface::ReleaseHostDisplay()
{
	m_display->DestroyRenderDevice();
	m_display.reset();
	m_display = NULL;
}

std::unique_ptr<AudioStream> OpenEmuHostInterface::CreateAudioStream(AudioBackend backend)
{
	return std::make_unique<OpenEmuAudioStream>();
}

void OpenEmuHostInterface::LoadSettings()
{
	
}

bool OpenEmuHostInterface::CreateDisplay()
{
	std::unique_ptr<HostDisplay> display = std::make_unique<OpenEmuOpenGLHostDisplay>();
	WindowInfo wi = WindowInfoFromGameCore(_current);
	if (!display->CreateRenderDevice(wi, "", g_settings.gpu_use_debug_device) ||
		!display->InitializeRenderDevice(GetShaderCacheBasePath(), g_settings.gpu_use_debug_device)) {
		ReportError("Failed to create/initialize display render device");
		return false;
	}
//	
	m_display = std::move(display);
	return true;
}

void OpenEmuHostInterface::ApplyGameSettings(bool display_osd_messages)
{
	// this gets called while booting, so can't use valid
	if (System::IsShutdown() || System::GetRunningCode().empty() || !g_settings.apply_game_settings)
		return;
	
	const GameSettings::Entry* gs = GetGameFixes(System::GetRunningCode());
	if (gs) {
		gs->ApplySettings(display_osd_messages);
	} else {
		Log_InfoPrintf("Unable to find game-specific settings for %s.", System::GetRunningCode().c_str());
	}
}

void OpenEmuHostInterface::OnRunningGameChanged()
{
	HostInterface::OnRunningGameChanged();

	Settings old_settings(std::move(g_settings));
	ApplyGameSettings(false);
	FixIncompatibleSettings(false);
	CheckForSettingsChanges(old_settings);
}

bool OpenEmuHostInterface::LoadCompatibilitySettings(const char* path)
{
	return m_game_settings.Load(path);
}

const GameSettings::Entry* OpenEmuHostInterface::GetGameFixes(const std::string& game_code)
{
	return m_game_settings.GetEntry(game_code);
}

#pragma mark OpenEmuAudioStream methods -

OpenEmuAudioStream::OpenEmuAudioStream()=default;
OpenEmuAudioStream::~OpenEmuAudioStream()=default;

void OpenEmuAudioStream::FramesAvailable()
{
	const u32 num_frames = GetSamplesAvailable();
	ReadFrames(m_output_buffer.data(), num_frames, false);
	id<OEAudioBuffer> rb = [_current audioBufferAtIndex:0];
	[rb write:m_output_buffer.data() maxLength:num_frames * m_channels * sizeof(SampleType)];
}

#pragma mark - Controller mapping

static void updateDigitalControllerButton(OEPSXButton button, int player, bool down) {
    DigitalController* controller = static_cast<DigitalController*>(System::GetController((u32)player));
    
	static constexpr std::array<std::pair<DigitalController::Button, OEPSXButton>, 14> mapping = {
		{{DigitalController::Button::Left, OEPSXButtonLeft},
			{DigitalController::Button::Right, OEPSXButtonRight},
			{DigitalController::Button::Up, OEPSXButtonUp},
			{DigitalController::Button::Down, OEPSXButtonDown},
			{DigitalController::Button::Circle, OEPSXButtonCircle},
			{DigitalController::Button::Cross, OEPSXButtonCross},
			{DigitalController::Button::Triangle, OEPSXButtonTriangle},
			{DigitalController::Button::Square, OEPSXButtonSquare},
			{DigitalController::Button::Start, OEPSXButtonStart},
			{DigitalController::Button::Select, OEPSXButtonSelect},
			{DigitalController::Button::L1, OEPSXButtonL1},
			{DigitalController::Button::L2, OEPSXButtonL2},
			{DigitalController::Button::R1, OEPSXButtonR1},
			{DigitalController::Button::R2, OEPSXButtonR2}}};
    
	for (const auto& it : mapping) {
		if (it.second == button) {
			controller->SetButtonState(it.first, down);
			break;
		}
	}
}

static void updateAnalogControllerButton(OEPSXButton button, int player, bool down) {
    AnalogController* controller = static_cast<AnalogController*>(System::GetController((u32)player));
    
	static constexpr std::array<std::pair<AnalogController::Button, OEPSXButton>, 17> button_mapping = {
		{{AnalogController::Button::Left, OEPSXButtonLeft},
			{AnalogController::Button::Right, OEPSXButtonRight},
			{AnalogController::Button::Up, OEPSXButtonUp},
			{AnalogController::Button::Down, OEPSXButtonDown},
			{AnalogController::Button::Circle, OEPSXButtonCircle},
			{AnalogController::Button::Cross, OEPSXButtonCross},
			{AnalogController::Button::Triangle, OEPSXButtonTriangle},
			{AnalogController::Button::Square, OEPSXButtonSquare},
			{AnalogController::Button::Start, OEPSXButtonStart},
			{AnalogController::Button::Select, OEPSXButtonSelect},
			{AnalogController::Button::L1, OEPSXButtonL1},
			{AnalogController::Button::L2, OEPSXButtonL2},
			{AnalogController::Button::L3, OEPSXButtonL3},
			{AnalogController::Button::R1, OEPSXButtonR1},
			{AnalogController::Button::R2, OEPSXButtonR2},
			{AnalogController::Button::R3, OEPSXButtonR3},
			{AnalogController::Button::Analog, OEPSXButtonAnalogMode}}};
    
	for (const auto& it : button_mapping) {
		if (it.second == button) {
			controller->SetButtonState(it.first, down);
			break;
		}
	}
}

static void updateAnalogAxis(OEPSXButton button, int player, CGFloat amount) {
    AnalogController* controller = static_cast<AnalogController*>(System::GetController((u32)player));
    
	static constexpr std::array<std::pair<AnalogController::Axis, std::pair<OEPSXButton, OEPSXButton>>, 4> axis_mapping = {
		{{AnalogController::Axis::LeftX, {OEPSXLeftAnalogLeft, OEPSXLeftAnalogRight}},
			{AnalogController::Axis::LeftY, {OEPSXLeftAnalogUp, OEPSXLeftAnalogDown}},
			{AnalogController::Axis::RightX, {OEPSXRightAnalogLeft, OEPSXRightAnalogRight}},
			{AnalogController::Axis::RightY, {OEPSXRightAnalogUp, OEPSXRightAnalogDown}}}};
	for (const auto& it : axis_mapping) {
        if (it.second.first == button || it.second.second == button) {
            controller->SetAxisState(it.first, static_cast<u8>(std::clamp(((static_cast<float>(amount) + 1.0f) / 2.0f) * 255.0f, 0.0f, 255.0f)));
        }
	}
}

static WindowInfo WindowInfoFromGameCore(PlayStationGameCore *core)
{
	WindowInfo wi = WindowInfo();
	//wi.type = WindowInfo::Type::MacOS;
	wi.surface_width = 640;
	wi.surface_height = 480;
	return wi;
}
