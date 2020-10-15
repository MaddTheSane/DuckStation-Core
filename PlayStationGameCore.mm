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
#include "core/host_display.h"
#include "core/host_interface.h"
#include "common/audio_stream.h"
#include "core/digital_controller.h"
#include "core/analog_controller.h"
#include "frontend-common/opengl_host_display.h"
#include "frontend-common/game_settings.h"
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

static void updateAnalogAxis(OEPSXButton button, AnalogController *controller, CGFloat amount);
static void updateAnalogControllerButton(OEPSXButton button, AnalogController *controller, bool down);
static void updateDigitalControllerButton(OEPSXButton button, DigitalController *controller, bool down);
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
	void DestroyRenderDevice() override;
	
	void ResizeRenderWindow(s32 new_window_width, s32 new_window_height) override;
	
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
	
	void Render();

protected:
	bool AcquireHostDisplay() override;
	void ReleaseHostDisplay() override;
	std::unique_ptr<AudioStream> CreateAudioStream(AudioBackend backend) override;
	void OnSystemDestroyed() override;
	void CheckForSettingsChanges(const Settings& old_settings) override;
	void LoadSettings() override;
	
private:
	static void HardwareRendererContextReset();
	static void HardwareRendererContextDestroy();
	bool CreateDisplay();
	
	//retro_hw_render_callback m_hw_render_callback = {};
	std::unique_ptr<HostDisplay> m_hw_render_display;
	bool m_hw_render_callback_valid = false;
	
	//retro_rumble_interface m_rumble_interface = {};
	bool m_rumble_interface_valid = false;
	bool m_supports_input_bitmasks = false;
	bool m_interfaces_initialized = false;
};

@interface PlayStationGameCore () <OEPSXSystemResponderClient>

@end




@implementation PlayStationGameCore {
	OpenEmuHostInterface *duckInterface;
    NSString *bootPath;
    bool isInitialized;
}

static void logCallback(void* pUserParam, const char* channelName, const char* functionName,
			 LOGLEVEL level, const char* message)
{
	NSString *logStr = [NSString stringWithFormat:@"%s %s %d %s", channelName, functionName, level, message];
	printf("%s", logStr.UTF8String);
	NSLog(@"%@", logStr);
}

- (instancetype)init
{
	if (self = [super init]) {
		_current = self;
		Log::RegisterCallback(&logCallback, nullptr);
		Log::SetFilterLevel(LOGLEVEL_DEV);
		g_settings.gpu_renderer = GPURenderer::HardwareOpenGL;
		g_settings.controller_types[0] = ControllerType::AnalogController;
		duckInterface = new OpenEmuHostInterface();
       
	}
	return self;
}

- (BOOL)loadFileAtPath:(NSString *)path error:(NSError **)error
{
    bootPath = path;

    return true;
}

- (OEIntSize)aspectSize
{
	return (OEIntSize){ 4, 3 };
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
	switch (g_settings.controller_types[player-1]) {
		case ControllerType::AnalogController:
		{
			AnalogController* controller = static_cast<AnalogController*>(System::GetController(u32(player-1)));
			updateAnalogAxis(button, controller, value);
		}
			break;
			
		default:
			break;
	}
}

- (oneway void)didPushPSXButton:(OEPSXButton)button forPlayer:(NSUInteger)player {
	switch (g_settings.controller_types[player-1]) {
		case ControllerType::DigitalController:
		{
			DigitalController* controller = static_cast<DigitalController*>(System::GetController(u32(player-1)));
			updateDigitalControllerButton(button, controller, true);
		}
			break;
			
		case ControllerType::AnalogController:
		{
			AnalogController* controller = static_cast<AnalogController*>(System::GetController(u32(player-1)));
			updateAnalogControllerButton(button, controller, true);
		}
			break;
			
		default:
			break;
	}
}


- (oneway void)didReleasePSXButton:(OEPSXButton)button forPlayer:(NSUInteger)player {
	switch (g_settings.controller_types[player-1]) {
		case ControllerType::DigitalController:
		{
			DigitalController* controller = static_cast<DigitalController*>(System::GetController(u32(player-1)));
			updateDigitalControllerButton(button, controller, false);
		}
			break;
			
		case ControllerType::AnalogController:
		{
			AnalogController* controller = static_cast<AnalogController*>(System::GetController(u32(player-1)));
			updateAnalogControllerButton(button, controller, false);
		}
			break;
			
		default:
			break;
	}
}


- (void)fastForward:(BOOL)flag {
	
}

- (void)fastForwardAtSpeed:(CGFloat)fastForwardSpeed {
	
}

- (void)rewind:(BOOL)flag {
	
}

- (void)rewindAtSpeed:(CGFloat)rewindSpeed {
	
}

- (void)setFrameCallback:(void (^)(NSTimeInterval))block {
	
}

- (void)slowMotionAtSpeed:(CGFloat)slowMotionSpeed {
	
}

- (void)stepFrameBackward {
	
}

- (void)stepFrameForward {
	
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
    }
    
	System::RunFrame();
	
	duckInterface->Render();
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
	if (!m_gl_context)
	{
	  //Log_ErrorPrintf("Failed to create any GL context");
	  return false;
	}

	gladLoadGL();
	m_window_info = wi;
	m_window_info.surface_width = m_gl_context->GetSurfaceWidth();
	m_window_info.surface_height = m_gl_context->GetSurfaceHeight();
	return true;
}

void OpenEmuOpenGLHostDisplay::DestroyRenderDevice()
{
	OpenGLHostDisplay::DestroyRenderDevice();
}

void OpenEmuOpenGLHostDisplay::ResizeRenderWindow(s32 new_window_width, s32 new_window_height) {
	
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
	
}

void OpenEmuHostInterface::ReportMessage(const char* message)
{
	
}

bool OpenEmuHostInterface::ConfirmMessage(const char* message)
{
	return true;
}

void OpenEmuHostInterface::AddOSDMessage(std::string message, float duration)
{
	
}

void OpenEmuHostInterface::GetGameInfo(const char* path, CDImage* image, std::string* code, std::string* title)
{
	if (image)
	  *code = System::GetGameCodeForImage(image);
}

std::string OpenEmuHostInterface::GetSharedMemoryCardPath(u32 slot) const
{
	return "";
}

std::string OpenEmuHostInterface::GetGameMemoryCardPath(const char* game_code, u32 slot) const
{
	return [_current.batterySavesDirectoryPath stringByAppendingPathComponent:[NSString stringWithFormat:@"%s-%d.mcd", game_code, slot]].fileSystemRepresentation;
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
	if (m_hw_render_display) {
		m_hw_render_display->DestroyRenderDevice();
		m_hw_render_display.reset();
	}
	
	m_display->DestroyRenderDevice();
	m_display.reset();
	m_display = NULL;
}

std::unique_ptr<AudioStream> OpenEmuHostInterface::CreateAudioStream(AudioBackend backend)
{
	return std::make_unique<OpenEmuAudioStream>();
}

void OpenEmuHostInterface::OnSystemDestroyed()
{
  HostInterface::OnSystemDestroyed();
}

void OpenEmuHostInterface::CheckForSettingsChanges(const Settings& old_settings)
{
	HostInterface::CheckForSettingsChanges(old_settings);
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

#pragma mark OpenEmuAudioStream methods -

OpenEmuAudioStream::OpenEmuAudioStream()=default;
OpenEmuAudioStream::~OpenEmuAudioStream()=default;

void OpenEmuAudioStream::FramesAvailable()
{
	const u32 num_frames = GetSamplesAvailable();
	ReadFrames(m_output_buffer.data(), num_frames, false);
	id<OEAudioBuffer> rb = [_current audioBufferAtIndex:0];
	[rb write:m_output_buffer.data() maxLength:num_frames * sizeof(SampleType)];
}

#pragma mark - Controller mapping

static void updateDigitalControllerButton(OEPSXButton button, DigitalController *controller, bool down) {
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
			controller->SetButtonState(it.first, !down);
			break;
		}
	}
}

static void updateAnalogControllerButton(OEPSXButton button, AnalogController *controller, bool down) {
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
			controller->SetButtonState(it.first, !down);
			break;
		}
	}
}

static void updateAnalogAxis(OEPSXButton button, AnalogController *controller, CGFloat amount) {
	static constexpr std::array<std::pair<AnalogController::Axis, std::pair<OEPSXButton, OEPSXButton>>, 4> axis_mapping = {
		{{AnalogController::Axis::LeftX, {OEPSXLeftAnalogLeft, OEPSXLeftAnalogRight}},
			{AnalogController::Axis::LeftY, {OEPSXLeftAnalogUp, OEPSXLeftAnalogDown}},
			{AnalogController::Axis::RightX, {OEPSXRightAnalogLeft, OEPSXRightAnalogRight}},
			{AnalogController::Axis::RightY, {OEPSXRightAnalogUp, OEPSXRightAnalogDown}}}};
	for (const auto& it : axis_mapping) {
		if (it.second.first == button) {
			controller->SetAxisState(it.first, std::clamp(static_cast<float>(amount) / 32767.0f, -1.0f, 1.0f));
			return;
		} else if (it.second.second == button) {
			controller->SetAxisState(it.first, std::clamp(static_cast<float>(amount) / -32767.0f, -1.0f, 1.0f));
			return;
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
