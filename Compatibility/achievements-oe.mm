
// Stubs for achievements. Obj-C++ for when OpenEmu adds support.

#define IMGUI_DEFINE_MATH_OPERATORS

#include "achievements.h"
//#include "achievements_private.h"
#include "bios.h"
#include "bus.h"
#include "cpu_core.h"
#include "fullscreen_ui.h"
#include "host.h"
#include "system.h"

#include "scmversion/scmversion.h"

#include "common/assert.h"
#include "common/error.h"
#include "common/file_system.h"
#include "common/log.h"
#include "common/md5_digest.h"
#include "common/path.h"
#include "common/scoped_guard.h"
#include "common/small_string.h"
#include "common/string_util.h"

#include "util/cd_image.h"
#include "util/http_downloader.h"
#include "util/imgui_fullscreen.h"
#include "util/imgui_manager.h"
#include "util/platform_misc.h"
#include "util/state_wrapper.h"

#include <algorithm>
#include <atomic>
#include <cstdarg>
#include <cstdlib>
#include <ctime>
#include <functional>
#include <string>
#include <vector>

Log_SetChannel(Achievements);

static std::recursive_mutex s_achievements_mutex;

bool Achievements::IsUsingRAIntegration()
{
  return false;
}

void Achievements::IdleUpdate()
{
	
}

bool Achievements::Initialize()
{
	return false;
}

void Achievements::FrameUpdate() {
	
}

void Achievements::GameChanged(const std::string& path, CDImage* image)
{
	
}

void Achievements::ResetClient()
{
	
}

void Achievements::OnSystemPaused(bool paused)
{
	
}

void Achievements::UpdateSettings(const Settings& old_config)
{
	
}

bool Achievements::ResetHardcoreMode()
{
	return false;
}

bool Achievements::ConfirmSystemReset()
{
	return false;
}

void Achievements::DisableHardcoreMode()
{
	
}

bool Achievements::IsHardcoreModeActive()
{
	return false;
}

bool Achievements::ConfirmHardcoreModeDisable(const char* trigger)
{
	return false;
}

void Achievements::ConfirmHardcoreModeDisableAsync(const char* trigger, std::function<void(bool)> callback)
{
	callback(false);
}

bool Achievements::DoState(StateWrapper& sw)
{
	// if we're inactive, we still need to skip the data (if any)
	if (!IsActive())
	{
	  u32 data_size = 0;
	  sw.Do(&data_size);
	  if (data_size > 0)
		sw.SkipBytes(data_size);

	  return !sw.HasError();
	}
	
#if 0
	std::unique_lock lock(s_achievements_mutex);

	if (sw.IsReading())
	{
		
	} else {
		
	}
#endif

	return true;
}

bool Achievements::IsActive()
{
	return false;
}

bool Achievements::Shutdown(bool allow_cancel)
{
	return true;
}
