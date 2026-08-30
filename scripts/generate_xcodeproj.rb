#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "xcodeproj"

root = File.expand_path("..", __dir__)
project_path = File.join(root, "YouShot.xcodeproj")

if File.exist?(project_path)
  abort "#{project_path} already exists; remove it explicitly before regenerating."
end

project = Xcodeproj::Project.new(project_path)
project.root_object.attributes["LastSwiftUpdateCheck"] = "2600"
project.root_object.attributes["LastUpgradeCheck"] = "2600"

target = project.new_target(:application, "YouShot", :osx, "14.0")
project.root_object.attributes["TargetAttributes"] = {
  target.uuid => {
    "CreatedOnToolsVersion" => "26.0",
  },
}

sources_group = project.main_group.new_group("Sources", "Sources")
youshot_group = sources_group.new_group("YouShot", "YouShot")
source_references = Dir.glob(File.join(root, "Sources/YouShot/*.swift")).sort.map do |path|
  youshot_group.new_file(File.basename(path))
end
target.add_file_references(source_references)

resources_group = project.main_group.new_group("Resources", "Resources")
info_plist = resources_group.new_file("Info.plist")
menu_bar_icon = resources_group.new_file("MenuBarIcon.png")
resources_group.new_file("MenuBarIcon.svg")
target.resources_build_phase.add_file_reference(menu_bar_icon, true)

icon_composer_reference = project.main_group.new_file("youshot.icon")
icon_composer_reference.last_known_file_type = "folder.iconcomposer.icon"
target.resources_build_phase.add_file_reference(icon_composer_reference, true)

project.main_group.new_file("Package.swift")
project.main_group.new_file("AGENTS.md")

project.build_configurations.each do |configuration|
  settings = configuration.build_settings
  settings["CLANG_ENABLE_MODULES"] = "YES"
  settings["MACOSX_DEPLOYMENT_TARGET"] = "14.0"
  settings["SDKROOT"] = "macosx"
  settings["SWIFT_VERSION"] = "6.0"
end

target.build_configurations.each do |configuration|
  settings = configuration.build_settings
  settings["ASSETCATALOG_COMPILER_APPICON_NAME"] = "youshot"
  settings["CODE_SIGN_STYLE"] = "Automatic"
  settings["COMBINE_HIDPI_IMAGES"] = "YES"
  settings["CURRENT_PROJECT_VERSION"] = "1"
  settings["ENABLE_HARDENED_RUNTIME"] = "YES"
  settings["GENERATE_INFOPLIST_FILE"] = "NO"
  settings["INFOPLIST_FILE"] = info_plist.real_path.relative_path_from(project.path.dirname).to_s
  settings["LD_RUNPATH_SEARCH_PATHS"] = "$(inherited) @executable_path/../Frameworks"
  settings["MARKETING_VERSION"] = "1.0.0"
  settings["PRODUCT_BUNDLE_IDENTIFIER"] = "com.youshot.app"
  settings["PRODUCT_NAME"] = "$(TARGET_NAME)"
  settings["SWIFT_EMIT_LOC_STRINGS"] = "YES"
end

project.save

scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(target)
scheme.set_launch_target(target)
scheme.save_as(project_path, "YouShot", true)

puts "Generated #{project_path}"
