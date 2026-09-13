{ pkgs ? import <nixpkgs> {} }:
let
  repoRoot = builtins.toString ./.;
  simBuild = "${repoRoot}/sim/tb/sim_build";
  simTb    = "${repoRoot}/sim/tb";
in
pkgs.mkShell {
  buildInputs = [
    pkgs.zlib
    pkgs.python3Packages.cocotb
    pkgs.python3Packages.cocotb-bus
    pkgs.python3Packages.find-libpython
  ];

  PYTHONPATH = "${pkgs.python3Packages.cocotb}/${pkgs.python3.sitePackages}:${pkgs.python3Packages.cocotb-bus}/${pkgs.python3.sitePackages}:${pkgs.python3Packages.find-libpython}/${pkgs.python3.sitePackages}";
  CPATH = "${pkgs.zlib.dev}/include";
  LIBRARY_PATH = "${pkgs.zlib}/lib";

  shellHook = ''
    run() { WAVES=1 python "$@"; }
    export -f run

    test() {
      local module=$1
      local testcase=$2
      local tb="${simTb}/test_''${module}.py"

      if [ -z "$module" ]; then
        echo "usage: test <module> [testcase]"
        echo "modules: $(ls ${simTb}/test_*.py 2>/dev/null | sed 's|.*test_||;s|\.py||' | tr '\n' ' ')"
        return 1
      fi

      if [ ! -f "$tb" ]; then
        echo "no testbench: $tb"
        return 1
      fi

      if [ -z "$testcase" ]; then
        (cd "${simTb}" && python "test_''${module}.py")
        if [ -f "${simBuild}/dump.fst" ]; then
          mv "${simBuild}/dump.fst" "${simBuild}/''${module}.fst"
        fi
      else
        (cd "${simTb}" && COCOTB_TESTCASE="$testcase" WAVES=1 python "test_''${module}.py")
        if [ -f "${simBuild}/dump.fst" ]; then
          mv "${simBuild}/dump.fst" "${simBuild}/''${module}.''${testcase}.fst"
        fi
      fi
    }
    export -f test

    _test_complete() {
      local cur=''${COMP_WORDS[COMP_CWORD]}
      local module=''${COMP_WORDS[1]}

      if [ "''${COMP_CWORD}" -eq 1 ]; then
        local modules
        modules=$(ls ${simTb}/test_*.py 2>/dev/null | sed 's|.*test_||;s|\.py||')
        COMPREPLY=($(compgen -W "$modules" -- "$cur"))
      elif [ "''${COMP_CWORD}" -eq 2 ]; then
        if [ -f "${simTb}/test_''${module}.py" ]; then
          local tests
          tests=$(grep -oP '(?<=async def )(test_\w+)' "${simTb}/test_''${module}.py")
          COMPREPLY=($(compgen -W "$tests" -- "$cur"))
        fi
      fi
    }
    complete -F _test_complete test

    wave() {
      local file=$1
      if [ -z "$file" ]; then
        echo "usage: wave <file.fst>"
        echo "available: $(ls ${simBuild}/*.fst 2>/dev/null | sed 's|.*/||' | tr '\n' ' ')"
        return 1
      fi
      # accept bare name (uart) or full path
      if [ ! -f "$file" ]; then
        file="${simBuild}/''${file%.fst}.fst"
      fi
      nohup surfer "$file" >/dev/null 2>&1 &
    }
    export -f wave

    _wave_complete() {
      local cur=''${COMP_WORDS[COMP_CWORD]}
      if [ "''${COMP_CWORD}" -eq 1 ]; then
        local files
        files=$(ls ${simBuild}/*.fst 2>/dev/null | sed 's|.*/||')
        COMPREPLY=($(compgen -W "$files" -- "$cur"))
      fi
    }
    complete -F _wave_complete wave

    doc() {
      python3 "$(git rev-parse --show-toplevel)/docs/gendoc.py" "$@"
    }
    export -f doc
  '';
}
