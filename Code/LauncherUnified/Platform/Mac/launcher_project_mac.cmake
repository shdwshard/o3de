#
# Copyright (c) Contributors to the Open 3D Engine Project.
# For complete copyright and license terms please see the LICENSE at the root of this distribution.
#
# SPDX-License-Identifier: Apache-2.0 OR MIT
#
#

set(LY_TARGET_PROPERTIES
    BUILD_RPATH @executable_path/
)

if(launcher_generator_BUILD_GENERIC)
    return()
endif()

# Add resources and app icons to launchers
# Skip resource check for generic launchers (when building the O3DE framework itself)
if(NOT DEFINED launcher_generator_BUILD_GENERIC OR NOT launcher_generator_BUILD_GENERIC)
    list(APPEND candidate_paths ${project_real_path}/Resources/Platform/Mac)
    list(APPEND candidate_paths ${project_real_path}/Gem/Resources/Platform/Mac) # Legacy projects
    list(APPEND candidate_paths ${project_real_path}/Gem/Resources/MacLauncher) # Legacy projects
    # LAST RESORT ONLY. The template's Info.plist contains PROJECT-CREATION tokens --
    # CFBundleExecutable is "${Name}.GameLauncher" -- and ${Name} is undefined at configure
    # time, so it expands to empty. The bundle then declares its executable as
    # ".GameLauncher", which does not exist, and fixup_bundle rejects the whole app with
    # "error: fixup_bundle: not a valid bundle". Listing this FIRST silently shadowed the
    # project's own correct Info.plist.
    list(APPEND candidate_paths ${LY_ROOT_FOLDER}/Templates/MinimalProject/Template/Resources/Platform/Mac)
    foreach(resource_path IN LISTS candidate_paths)
        if(EXISTS ${resource_path})
            set(ly_game_resource_folder ${resource_path})
            break()
        endif()
    endforeach()

    if(NOT EXISTS ${ly_game_resource_folder})
        list(JOIN candidate_paths " " formatted_error)
        message(FATAL_ERROR "Missing 'Resources' folder. Candidate paths tried were: ${formatted_error}")
    endif()

    # Only add resources if we found them
    target_sources(${project_name}.GameLauncher PRIVATE ${ly_game_resource_folder}/Images.xcassets)
    set_target_properties(${project_name}.GameLauncher PROPERTIES
        MACOSX_BUNDLE_INFO_PLIST ${ly_game_resource_folder}/Info.plist
        RESOURCE ${ly_game_resource_folder}/Images.xcassets
        XCODE_ATTRIBUTE_ASSETCATALOG_COMPILER_APPICON_NAME ${project_name}AppIcon
    )
else()
    # For generic launchers, set minimal properties without resources
    set_target_properties(${project_name}.GameLauncher PROPERTIES
        XCODE_ATTRIBUTE_ASSETCATALOG_COMPILER_APPICON_NAME ${project_name}AppIcon
    )
endif()

set(layout_tool_dir ${LY_ROOT_FOLDER}/cmake/Tools)

add_custom_command(TARGET ${project_name}.GameLauncher POST_BUILD
    COMMAND ${LY_PYTHON_CMD} layout_tool.py
        -p Mac
        -a ${LY_ASSET_DEPLOY_ASSET_TYPE}
        --project-path ${project_real_path}
        -m ${LY_ASSET_DEPLOY_MODE}
        --create-layout-root
        -l $<TARGET_BUNDLE_DIR:${project_name}.GameLauncher>/Contents/Resources/assets
        --build-config $<CONFIG>
        --warn-on-missing-assets
        --verify
        ${LY_OVERRIDE_PAK_ARGUMENT}
    WORKING_DIRECTORY ${layout_tool_dir}
    COMMENT "Synchronizing Layout Assets ..."
    VERBATIM
)
