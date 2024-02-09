// SPDX-FileCopyrightText: 2019-2022 Connor McLaughlin <stenzek@gmail.com>
// SPDX-License-Identifier: (GPL-3.0 OR CC-BY-NC-ND-4.0)

#include "platform_misc.h"
#include "window_info.h"
#include "metal_layer.h"

#include "common/log.h"
#include "common/small_string.h"

#include <Cocoa/Cocoa.h>
#include <QuartzCore/QuartzCore.h>
#include "DuckStationGameCore.h"
#include <cinttypes>
#include <vector>

Log_SetChannel(PlatformMisc);


void PlatformMisc::SuspendScreensaver()
{
}

void PlatformMisc::ResumeScreensaver()
{
}

bool CocoaTools::CreateMetalLayer(WindowInfo *wi)
{
	// Punt off to main thread if we're not calling from it already.
	if (![NSThread isMainThread])
	{
		bool ret;
		dispatch_sync(dispatch_get_main_queue(), [&ret, wi]() {
			ret = CreateMetalLayer(wi);
		});
		return ret;
	}
	
	CAMetalLayer* layer = [CAMetalLayer layer];
	if (layer == nil)
	{
		Log_ErrorPrint("Failed to create CAMetalLayer");
		return false;
	}
	
	NSView* view = (__bridge NSView*)wi->window_handle;
	[view setWantsLayer:TRUE];
	[view setLayer:layer];
	[layer setContentsScale:[[[view window] screen] backingScaleFactor]];
	
	wi->surface_handle = (void*)CFBridgingRetain(layer);
	return true;
}

void CocoaTools::DestroyMetalLayer(WindowInfo *wi)
{
	if (!wi->surface_handle)
		return;
	
	// Punt off to main thread if we're not calling from it already.
	if (![NSThread isMainThread])
	{
		dispatch_sync(dispatch_get_main_queue(), [wi]() { DestroyMetalLayer(wi); });
		return;
	}
	
	NSView* view = (__bridge NSView*)wi->window_handle;
	CAMetalLayer* layer = CFBridgingRelease(wi->surface_handle);
	[view setLayer:nil];
	[view setWantsLayer:NO];
	//  [layer release];
}
