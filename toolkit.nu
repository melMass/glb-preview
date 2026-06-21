const here = (path self | path dirname)

def levels [] {
  [
    debug
    info
    default
    error
    fault
  ]
}

export def watch-logs [--level: string@levels = "info"] {
  log stream --predicate 'subsystem == "com.laurie.GLBPreview.PreviewExtension"' --level $level
}

# Headless build, install, and Quick Look reset for GLBPreview
export def build [
  --release (-r) # Release configuration (default: Debug)
  --test: path # Test preview with qlmanage -p on a .glb file
  --no-install # Build only, skip install + QL reset
] {
  let config = if $release { "Release" } else { "Debug" }
  let derived = ($here | path join .derivedData)

  print $"(ansi yd)xcodegen generate(ansi reset)"
  let gen = (do { cd $here; ^xcodegen generate | complete })
  if $gen.exit_code != 0 {
    print $"(ansi red)xcodegen failed:(ansi reset)\n($gen.stderr)"
    return
  }

  print $"(ansi c)xcodebuild (($config))...(ansi reset)"
  let result = (
    do {
      cd $here
      ^xcodebuild -scheme GLBPreview -configuration $config -derivedDataPath $derived -quiet build "CODE_SIGN_STYLE=Manual" "CODE_SIGN_IDENTITY=-" "PROVISIONING_PROFILE_SPECIFIER=" "DEVELOPMENT_TEAM=" | complete
    }
  )
  if $result.exit_code != 0 {
    print $"(ansi red)Build failed:(ansi reset)\n($result.stdout)\n($result.stderr)"
    return
  }
  print $"(ansi g)Build succeeded(ansi reset)"

  if not $no_install {
    let app = ($derived | path join Build Products $config GLBPreview.app)
    if not ($app | path exists) {
      print $"(ansi red)App bundle not found at ($app)(ansi reset)"
      return
    }

    print $"(ansi c)Installing to /Applications...(ansi reset)"
    rm -rf /Applications/GLBPreview.app
    cp -r $app /Applications/GLBPreview.app

    ^qlmanage -r o+e>| ignore
    ^qlmanage -r cache o+e>| ignore
    print $"(ansi g)Installed + QL cache reset(ansi reset)"
  }

  if ($test | is-not-empty) {
    print $"\n(ansi yd)qlmanage -p ($test)(ansi reset)"
    ^qlmanage -p ($test | path expand)
  }
}
