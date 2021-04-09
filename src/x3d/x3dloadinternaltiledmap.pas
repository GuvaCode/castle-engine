{
  Copyright 2020-2021 Matthias J. Molski.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Convert tiled map (created by Tiled; See https://www.mapeditor.org/)
  into X3D scene representation. }
unit X3DLoadInternalTiledMap;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, Math,
  X3DNodes, CastleTiledMap, CastleVectors, CastleTransform, CastleColors,
  CastleRenderOptions, X3DLoadInternalImage;

function LoadTiledMap2d(const Stream: TStream; const BaseUrl: String
  ): TX3DRootNode;

implementation

function LoadTiledMap2d(const Stream: TStream; const BaseUrl: String
  ): TX3DRootNode;
var
  ATiledMap: TTiledMap;
begin

end;

end.

