source 'https://github.com/CocoaPods/Specs.git'

minVersion = '10.13'

platform :osx, minVersion

# cocoapods-prune-localizations doesn't appear to auto-detect pods properly, so using a manual list
supported_locales = ['Base', 'da', 'de', 'en', 'es', 'fr', 'it', 'ja', 'ko', 'nl', 'pt-BR', 'sv', 'tr', 'zh-Hans']
plugin 'cocoapods-prune-localizations', { :localizations => supported_locales }

target "SelfControl" do
    use_frameworks! :linkage => :static
    pod 'MASPreferences', '~> 1.1.4'
    pod 'TransformerKit', '~> 1.1.1'
    pod 'FormatterKit/TimeIntervalFormatter', '~> 1.8.0'
    pod 'LetsMove', '~> 1.24'
    pod 'Sentry', '~> 7.31'

    # Add test target
    target 'SelfControlTests' do
        inherit! :complete
    end
end

target "SelfControl Killer" do
    use_frameworks! :linkage => :static
    pod 'Sentry', '~> 7.31'
end

# we can't use_frameworks on these because they're command-line tools
target "SCKillerHelper" do
    pod 'Sentry', '~> 7.31'
end
target "selfcontrol-cli" do
    pod 'Sentry', '~> 7.31'
end
target "org.eyebeam.selfcontrold" do
    pod 'Sentry', '~> 7.31'
end

post_install do |pi|
   # Fix 1: Xcode 16 / clang 17 no longer transitively exposes std::terminate_handler
   # from <typeinfo>; we need <exception> explicitly.
   sentry_cpp = "#{pi.sandbox.root}/Sentry/Sources/SentryCrash/Recording/Monitors/SentryCrashMonitor_CPPException.cpp"
   if File.exist?(sentry_cpp)
       content = File.read(sentry_cpp)
       unless content.include?('#include <exception>')
           File.write(sentry_cpp, content.sub('#include <typeinfo>', "#include <exception>\n#include <typeinfo>"))
       end
   end

   # Fix 2: @import Darwin.Availability is removed in macOS 15.5 SDK; use #include instead.
   # Patch all TransformerKit source files that use it.
   Dir.glob("#{pi.sandbox.root}/TransformerKit/Sources/**/*.{h,m}").each do |f|
       content = File.read(f)
       patched = content.gsub('@import Darwin.Availability;', '#include <Availability.h>')
       File.write(f, patched) if patched != content
   end

   # Fix 3: macOS SDK 15.5 libc++ rejects std::vector<const T>; remove the const.
   sentry_cache_hpp = "#{pi.sandbox.root}/Sentry/Sources/Sentry/include/SentryThreadMetadataCache.hpp"
   if File.exist?(sentry_cache_hpp)
       content = File.read(sentry_cache_hpp)
       patched = content
           .gsub('std::vector<const ThreadHandleMetadataPair>', 'std::vector<ThreadHandleMetadataPair>')
           .gsub('std::vector<const QueueMetadata>', 'std::vector<QueueMetadata>')
       File.write(sentry_cache_hpp, patched) if patched != content
   end

   # Fix 4: CocoaPods generates a resources script looking for the MASPreferences .nib
   # at the framework root, but macOS versioned frameworks put resources inside
   # Versions/Current/Resources/. Patch the generated script to use the correct path.
   resources_script = "#{pi.sandbox.root}/Target Support Files/Pods-SelfControl/Pods-SelfControl-resources.sh"
   if File.exist?(resources_script)
       content = File.read(resources_script)
       patched = content.gsub(
           'MASPreferences.framework/en.lproj/MASPreferencesWindow.nib',
           'MASPreferences.framework/Resources/en.lproj/MASPreferencesWindow.nib'
       )
       File.write(resources_script, patched) if patched != content
   end

   pi.pods_project.targets.each do |t|
       t.build_configurations.each do |bc|
           if Gem::Version.new(bc.build_settings['MACOSX_DEPLOYMENT_TARGET'].to_s) < Gem::Version.new(minVersion)
               bc.build_settings['MACOSX_DEPLOYMENT_TARGET'] = minVersion
           end
           # Fix: Darwin module no longer exposes 'Availability' as a submodule in Xcode 15+.
           # Prevent TransformerKit from being built as a framework module (which triggers
           # the submodule scan), while keeping modules enabled so @import works internally.
           if t.name == 'TransformerKit'
               bc.build_settings['DEFINES_MODULE'] = 'NO'
               bc.build_settings['CLANG_ALLOW_NON_MODULAR_INCLUDES_IN_FRAMEWORK_MODULES'] = 'YES'
           end
           # Fix: Sentry 7.x C++ code uses patterns removed in C++17 (const allocator, terminate_handler).
           # Force C++14 for Sentry targets only.
           if t.name.include?('Sentry')
               bc.build_settings['CLANG_CXX_LANGUAGE_STANDARD'] = 'gnu++14'
           end
       end
   end
end
