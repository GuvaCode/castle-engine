{
  Copyright 2011-2011 Michalis Kamburelis.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Gaussian blur. }
unit Gaussian;

interface

function Gaussian2D(const X, Y, StdDev: Single): Single;

{ From a circle radius, derive standard deviation of Gaussian that fits
  nicely within this radius (filling this radius, with values outside
  of this circle practically zero). }
function RadiusToStdDev(const Radius: Single): Single;

implementation

uses Math;

function Gaussian2D(const X, Y, StdDev: Single): Single;
begin
  Result := Exp( -(Sqr(X) + Sqr(Y)) / (2 * Sqr(StdDev)) ) / (2 * Pi * Sqr(StdDev));
end;

function RadiusToStdDev(const Radius: Single): Single;
begin
  { GIMP equation below (see plug-ins/common/blur-gauss.c)
  Result := Sqrt (-Sqr(Radius + 1.0) / (2 * Ln(1.0 / 255.0))); }

  { We just take /2 for now. }
  Result := Radius / 2;
end;

end.
