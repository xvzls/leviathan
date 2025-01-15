{
	pkgs ? import <nixpkgs> {},
	unstable ? import (fetchTarball "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz") {},
}:
let
	zig = pkgs.stdenv.mkDerivation {
		name = "zig-0.14.0-dev";
		
		src = pkgs.fetchurl {
			url = "https://ziglang.org/builds/zig-linux-x86_64-0.14.0-dev.2643+fb43e91b2.tar.xz";
			hash = "sha256-SvyTITdW3+7OLh3RZhFZ6Sqh3iQG5Q7mYLFVt+kIt0Y=";
		};
		
		buildInputs = [
			unstable.libxml2
			unstable.zlib
		] ++ (with unstable.llvmPackages; [
			libclang
			lld
			llvm
		]);
		
		patchPhase = ''
			substituteInPlace lib/std/zig/system.zig --replace-fail "/usr/bin/env" "${pkgs.lib.getExe' pkgs.coreutils "env"}"
		'';
		
		installPhase = ''
			mkdir -p $out/lib
			mkdir -p $out/bin
			cp lib $out/lib/zig -r
			cp zig $out/bin/zig
		'';
	};
	zon_dependencies = pkgs.callPackage ./build.zig.zon.nix {};
in
unstable.python313Packages.buildPythonPackage {
	pname = "leviathan";
	version = "0.1.0";
	pyproject = true;
	
	src = ./.;
	
	C_INCLUDE_PATH = "${builtins.getEnv "C_INCLUDE_PATH"}:${unstable.python313}/include/${unstable.python313.libPrefix}";
	
	build-system = [
		unstable.python313Packages.setuptools
	];
	
	nativeBuildInputs = [
		# Zig
		unstable.zls
		zig
		pkgs.zon2nix
		
		# Python
		(unstable.python313.withPackages (py: [
			py.pytest
		]))
		unstable.python312Packages.pylsp-mypy
	];
	
	buildInputs = [
		# Python
		unstable.python313
	];
	
	checkInputs = [
		unstable.python313Packages.pytestCheckHook
	];
	
	doCheck = true;
	
	pytestCheckPhase = ''
		cd build/lib/
		python -m pytest -s
		cd
	'';
	
	patchPhase = ''
		export HOME=$TMPDIR
		export ZIG_GLOBAL_CACHE_DIR="$HOME/.cache/zig"
		mkdir -p "$ZIG_GLOBAL_CACHE_DIR"
		
		ln -s ${zon_dependencies} "$ZIG_GLOBAL_CACHE_DIR/p"
	'';
	
	meta = with pkgs.lib; {
		description = "Leviathan: A lightning-fast Zig-powered event loop for Python's asyncio";
		maintainers = [
			{
				email = "kike28.py@pm.me";
				github = "kython28";
				name = "Enrique Miguel Mora Meza";
			}
		];
		homepage = "https://github.com/kython28/leviathan";
		license = licenses.mit;
		platforms = platforms.gnu;
	};
}
