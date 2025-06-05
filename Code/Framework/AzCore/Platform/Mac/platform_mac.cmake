#
# Copyright (c) Contributors to the Open 3D Engine Project.
# For complete copyright and license terms please see the LICENSE at the root of this distribution.
#
# SPDX-License-Identifier: Apache-2.0 OR MIT
#
#

find_library(APPKIT_LIBRARY AppKit)
find_library(FOUNDATION_LIBRARY Foundation)

# Check macOS version - ScreenCaptureKit is only available on macOS 12.3+
execute_process(COMMAND sw_vers -productVersion OUTPUT_VARIABLE MACOS_VERSION OUTPUT_STRIP_TRAILING_WHITESPACE)
if(MACOS_VERSION VERSION_GREATER_EQUAL "12.3")
    find_library(SCREEN_CAPTURE_LIBRARY ScreenCaptureKit)
    find_library(CORE_MEDIA_LIBRARY CoreMedia)
    set(LY_BUILD_DEPENDENCIES
        PRIVATE
            ${APPKIT_LIBRARY}
            ${FOUNDATION_LIBRARY}
            ${SCREEN_CAPTURE_LIBRARY}
            ${CORE_MEDIA_LIBRARY}
    )
else()
    set(LY_BUILD_DEPENDENCIES
        PRIVATE
            ${APPKIT_LIBRARY}
            ${FOUNDATION_LIBRARY}
    )
endif()
