{ pkgs, fetchurl, fetchgit, fetchhg }:

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
}