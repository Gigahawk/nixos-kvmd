{ pkgs, fetchurl, fetchgit, fetchhg, fetchFromGitHub }:

self: super: {
  luma-oled = super.buildPythonPackage rec {
    pname = "luma.oled";
    version = "3.13.0";
    src = fetchurl {
      url = "https://files.pythonhosted.org/packages/3d/d2/924eb179fdf607874d7c93500d260aed02b2f5cb2a64e25d841f67b1ac55/luma.oled-3.13.0-py2.py3-none-any.whl";
      sha256 = "sha256-e/Ncg1Olk92uBSCCcA6CjGanET8R8zPWm+CLHASexxw=";
    };
    format = "wheel";
  };
  luma-core = super.buildPythonPackage rec {
    pname = "luma.core";
    version = "2.4.2";
    src = fetchurl {
      url = "https://files.pythonhosted.org/packages/6e/d0/f4022b3f17dec1bee5920526b4f2b7850ac2b70cc3420231bd498a828c6b/luma.core-2.4.2-py2.py3-none-any.whl";
      sha256 = "sha256-Xsy7395LjNkRPRvTVb5qKQQcCy5/VuGHOk7tNW6fxYI=";
    };
    format = "wheel";
  };
  # rpi-gpio2 was removed by nixpkgs#315371
  rpi-gpio2 = super.buildPythonPackage rec {
    pname = "rpi-gpio2";
    version = "0.4.0";
    format = "setuptools";

    # PyPi source does not work for some reason
    src = fetchFromGitHub {
      owner = "underground-software";
      repo = "RPi.GPIO2";
      rev = "refs/tags/v${version}";
      hash = "sha256-CNnej67yTh3C8n4cCA7NW97rlfIDrrlepRNDkv+BUeY=";
    };

    propagatedBuildInputs = [ super.libgpiod ];

    # Disable checks because they need to run on the specific platform
    doCheck = false;
  };
}