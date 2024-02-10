// Copyright (c) 2024, OpenEmu Team
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

#include "util/imgui_manager.h"
#include "core/imgui_overlays.h"
#include "util/input_manager.h"

void ImGuiManager::SetFontPathAndRange(std::string path, std::vector<u16> range)
{
	
}

void ImGuiManager::SetGlobalScale(float global_scale)
{
	
}

void ImGuiManager::SetShowOSDMessages(bool enable)
{
	
}

bool ImGuiManager::Initialize(float global_scale, bool show_osd_messages, Error* error)
{
	return true;
}

void ImGuiManager::Shutdown()
{
	
}

float ImGuiManager::GetWindowWidth()
{
	return 640;
}

float ImGuiManager::GetWindowHeight()
{
	return 480;
}

void ImGuiManager::WindowResized()
{
	
}

void ImGuiManager::UpdateScale()
{
	
}

void ImGuiManager::NewFrame()
{
	
}

void ImGuiManager::RenderOSDMessages()
{
	
}

float ImGuiManager::GetGlobalScale()
{
	return 1;
}

bool ImGuiManager::HasFullscreenFonts()
{
	return true;
}

bool ImGuiManager::AddFullscreenFontsIfMissing()
{
	return true;
}

ImFont* ImGuiManager::GetStandardFont()
{
	return nullptr;
}

ImFont* ImGuiManager::GetFixedFont()
{
	return nullptr;
}

ImFont* ImGuiManager::GetMediumFont()
{
	return nullptr;
}

ImFont* ImGuiManager::GetLargeFont()
{
	return nullptr;
}

bool ImGuiManager::WantsTextInput()
{
	return false;
}

bool ImGuiManager::WantsMouseInput()
{
	return false;
}

void ImGuiManager::AddTextInput(std::string str)
{
	
}

void ImGuiManager::UpdateMousePosition(float x, float y)
{
	
}

bool ImGuiManager::ProcessPointerButtonEvent(InputBindingKey key, float value)
{
	return false;
}

bool ImGuiManager::ProcessPointerAxisEvent(InputBindingKey key, float value)
{
	return false;
}

bool ImGuiManager::ProcessHostKeyEvent(InputBindingKey key, float value)
{
	return false;
}

bool ImGuiManager::ProcessGenericInputEvent(GenericInputBinding key, float value)
{
	return false;
}

void ImGuiManager::SetSoftwareCursor(u32 index, std::string image_path, float image_scale, u32 multiply_color)
{
	
}

bool ImGuiManager::HasSoftwareCursor(u32 index)
{
	return false;
}

void ImGuiManager::ClearSoftwareCursor(u32 index)
{
	
}

void ImGuiManager::SetSoftwareCursorPosition(u32 index, float pos_x, float pos_y)
{
	
}

void ImGuiManager::RenderSoftwareCursors()
{
	
}

void ImGuiManager::RenderTextOverlays()
{
	
}

void ImGuiManager::RenderDebugWindows()
{
	
}

void ImGuiManager::RenderOverlayWindows()
{
	
}

void ImGuiManager::DestroyOverlayTextures()
{
	
}

bool SaveStateSelectorUI::IsOpen()
{
	return false;
}

void SaveStateSelectorUI::Open(float open_time)
{
	
}

void SaveStateSelectorUI::RefreshList(const std::string& serial)
{
	
}

void SaveStateSelectorUI::Clear()
{
	
}

void SaveStateSelectorUI::ClearList()
{
	
}