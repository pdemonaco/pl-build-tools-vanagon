component "boost" do |pkg, settings, platform|
  pkg.version "1.58.0"
  pkg.md5sum "5a5d5614d9a07672e1ab2a250b5defc5"

  # Apparently boost doesn't use dots to version they use underscores....arg
  pkg.url "http://buildsources.delivery.puppetlabs.net/#{pkg.get_name}_#{pkg.get_version.gsub('.','_')}.tar.gz"

  boost_libs = [ 'atomic', 'chrono', 'container', 'date_time', 'exception', 'filesystem', 'graph', 'graph_parallel', 'iostreams', 'locale', 'log', 'math', 'program_options', 'random', 'regex', 'serialization', 'signals', 'system', 'test', 'thread', 'timer', 'wave' ]

  cflags = "-fPIC -std=c99"
  cxxflags = "-std=c++11 -fPIC"

  # These are all places where windows differs from *nix. These are the default *nix settings.
  toolset = "--with-toolset=gcc"
  boost_dir = ""
  bootstrap_suffix = ".sh"
  execute = "./"
  addtl_flags = ""

  # This is pretty horrible.  But so is package management on OSX.
  if platform.is_osx?
    pkg.build_requires "pl-gcc-4.8.2"
    gpp = "#{settings[:bindir]}/g++"
  elsif platform.is_solaris?
    if platform.os_version == "10"
      pkg.build_requires "http://pl-build-tools.delivery.puppetlabs.net/solaris/10/pl-gcc-4.8.2.#{platform.architecture}.pkg.gz"
      pkg.build_requires "http://pl-build-tools.delivery.puppetlabs.net/solaris/10/pl-binutils-2.25.#{platform.architecture}.pkg.gz"
    elsif platform.os_version == "11"
      pkg.build_requires "pl-binutils-#{platform.architecture}"
      pkg.build_requires "pl-gcc-#{platform.architecture}"
    end

    pkg.apply_patch 'resources/patches/boost/solaris-10-boost-build.patch'

    pkg.environment "PATH" => "#{settings[:basedir]}/bin:/usr/ccs/bin:/usr/sfw/bin:$$PATH"
    linkflags = "-Wl,-rpath=#{settings[:libdir]}"
    b2flags = "define=_XOPEN_SOURCE=600"

    if platform.architecture == "sparc"
      b2flags = "#{b2flags} instruction-set=v9"
    end

    gpp = "#{settings[:basedir]}/bin/#{settings[:platform_triple]}-g++"
  elsif platform.is_windows?
    arch = platform.architecture == "x64" ? "64" : "32"
    pkg.environment "PATH" => "#{platform.drive_root}/tools/mingw#{arch}/bin:$$PATH"
    pkg.environment "CYGWIN" => "nodosfilewarning"

    # bootstrap.bat does not take the `--with-toolset` flag
    toolset = "mingw"
    # boost is installed with this extra subdirectory on windows
    boost_dir = "boost-1_58"
    # we do not need to reference the .bat suffix when calling the bootstrap script
    bootstrap_suffix = ""
    # we need to make sure we link against non-cygwin libraries
    execute = "cmd.exe /c "

    # Sometimes we need to pass in the windows-specific path
    special_prefix = platform.convert_to_windows_path(settings[:prefix])

    gpp = platform.convert_to_windows_path("#{platform.drive_root}/tools/mingw#{arch}/bin/g++")

    # We don't have iconv available on windows yet
    addtl_flags = "boost.locale.iconv=off"
  else
    linkflags = "-Wl,-rpath=#{settings[:libdir]},-rpath=#{settings[:libdir]}64"
    pkg.build_requires "pl-gcc" unless platform.is_aix?

    case platform.name
    when /el|fedora/
      if platform.name =~ /el-4/
        pkg.build_requires 'pl-tar'
      end
      pkg.build_requires 'bzip2-devel'
      pkg.build_requires 'zlib-devel'
    when /aix/
      linkflags = "-Wl,-L#{settings[:libdir]}"
      pkg.environment "PATH" => "/opt/freeware/bin:#{settings[:basedir]}/bin:$$PATH"
      pkg.build_requires "http://pl-build-tools.delivery.puppetlabs.net/aix/#{platform.os_version}/ppc/pl-gcc-5.2.0-1.aix#{platform.os_version}.ppc.rpm"
      pkg.build_requires 'http://osmirror.delivery.puppetlabs.net/AIX_MIRROR/bzip2-1.0.5-3.aix5.3.ppc.rpm'
      pkg.build_requires 'http://osmirror.delivery.puppetlabs.net/AIX_MIRROR/zlib-devel-1.2.3-4.aix5.2.ppc.rpm'
      pkg.build_requires 'http://osmirror.delivery.puppetlabs.net/AIX_MIRROR/zlib-1.2.3-4.aix5.2.ppc.rpm'
    when /huaweios/
      pkg.build_requires "http://pl-build-tools.delivery.puppetlabs.net/HuaweiOS/#{platform.os_version}/ppce500mc/pl-gcc-4.8.2-1.huaweios6.ppce500mc.rpm"
      pkg.build_requires "http://pl-build-tools.delivery.puppetlabs.net/HuaweiOS/#{platform.os_version}/ppce500mc/pl-cmake-3.2.3-1.huaweios6.ppce500mc.rpm"
    when /sles-10/
      pkg.build_requires 'bzip2'
      pkg.build_requires 'zlib-devel'
    when /sles-(11|12)/
      pkg.build_requires 'libbz2-devel'
      pkg.build_requires 'zlib-devel'
    when /debian|ubuntu|Cumulus/i
      pkg.build_requires 'libbz2-dev'
      pkg.build_requires 'zlib1g-dev'
    end

    pkg.environment "PATH" => "#{settings[:bindir]}:$$PATH"
    b2flags = ""
    gpp = "#{settings[:bindir]}/g++"
  end

  if platform.is_osx?
    userconfigjam = %Q{using darwin : : #{gpp};}
  elsif platform.is_windows?
    userconfigjam = %Q{using gcc : : #{gpp} ;}
  else
    userconfigjam = %Q{using gcc : 4.8.2 : #{gpp} : <linkflags>"#{linkflags}" <cflags>"#{cflags}" <cxxflags>"#{cxxflags}" ;}
  end

  # On some platforms, we have multiple means of specifying paths. Sometimes, we need to use either one
  # form or another. `special_prefix` allows us to do this. i.e., on windows, we need to have the
  # windows specific path (C:/), whereas for everything else, we can default to the drive root currently
  # in use (/cygdrive/c). This has to do with how the program is built, where it is expecting to find
  # libraries and binaries, and how it tries to find them.
  pkg.build do
    [
      %Q{echo '#{userconfigjam}' > ~/user-config.jam},
      "cd tools/build",
      "#{execute}bootstrap#{bootstrap_suffix} #{toolset}",
      "./b2 install -d+2 \
      --prefix=#{special_prefix ? special_prefix : settings[:prefix]} \
      toolset=gcc \
      #{b2flags} \
      --debug-configuration"
    ]
  end

  #the following will remove the user-config.jam (from build) at the end of installation
  pkg.install do
    [ "#{settings[:prefix]}/bin/b2 \
    -d+2 \
    toolset=gcc \
    #{b2flags} \
    --debug-configuration \
    --build-dir=. \
    --prefix=#{special_prefix ? special_prefix : settings[:prefix]} \
    #{boost_libs.map {|lib| "--with-#{lib}"}.join(" ")} \
    #{addtl_flags} \
    install",
    "chmod 0644 #{settings[:includedir]}/#{boost_dir}/boost/graph/vf2_sub_graph_iso.hpp",
    "chmod 0644 #{settings[:includedir]}/#{boost_dir}/boost/thread/v2/shared_mutex.hpp",
    "rm -f ~/user-config.jam"
    ]
  end
end
