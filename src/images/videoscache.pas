{
  Copyright 2008-2012 Michalis Kamburelis.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ A cache for loading both videos and images (TImagesVideosCache). }
unit VideosCache;

interface

uses CastleUtils, ImagesCache, Videos, FGL;

type
  { Internal for TVideosCache. @exclude }
  TCachedVideo = class
    References: Cardinal;
    FileName: string;
    Video: TVideo;
  end;
  TCachedVideoList = specialize TFPGObjectList<TCachedVideo>;

  { A cache of loaded videos.

    The idea is that instead of creating TVideo instance and calling
    TVideo.LoadFromFile, you instead call
    @code(Video := Cache.Video_IncReference(...)).
    Later, instead of freeing this video, call
    @code(Video_DecReference(Video)). From your point of view, things
    will work the same. But if you expect to load many videos from the
    same FileName, then you will get a great speed and memory saving,
    because video will only be actually loaded once. This may happen
    e.g. if you have a VRML / X3D file with lots of MovieTexture nodes
    with the same urls.

    Notes:

    @unorderedList(
      @item(All passed here FileNames must be absolute, already expanded paths.
        In the future it's expected that this (just like TVideo.LoadFromFile,
        actually) will be extended to load videos from URLs.)

      @item(Note that in case of problems with loading,
        Video_IncReference may raise an exception, just like normal
        TVideo.LoadFromFile. In this case it's guaranteed that no reference will
        be incremented, of course. If Video_IncReference returns
        in a normal way, then it will return something non-@nil for sure.)

      @item(Video_DecReference alwas sets Video to @nil, like FreeAndNil.)

      @item(As TVideo also uses TImagesCache internally to load single
        images, and this class descends from TImagesCache, so we naturally
        set Self as TVideo.Cache. This way you also get images sharing,
        useful for example if your videos came from images sequence
        shared by other videos.)

      @item(All videos handled here are always loaded.
        So Video_IncReference always returns TVideo with TVideo.Loaded = @true.
        And you are forbidden from closing this video by TVideo.Close
        yourself.)
    )

    Note that before destroying this object you must free all videos,
    i.e. call Video_DecReference for all videos allocated by
    Video_IncReference. @italic(This class is not a lousy way
    of avoiding memory leaks) --- it would be a bad idea, because it would
    cause sloppy programming, where memory is unnecessarily allocated for
    a long time. In fact, this class asserts in destructor that no videos
    are in cache anymore, so if you compiled with assertions enabled,
    this class does the job of memory-leak detector. }
  TImagesVideosCache = class(TImagesCache)
  private
    CachedVideos: TCachedVideoList;
  public
    constructor Create;
    destructor Destroy; override;

    function Video_IncReference(const FileName: string): TVideo;
    procedure Video_DecReference(var Video: TVideo);

    function Empty: boolean; override;
  end;

implementation

uses SysUtils, CastleStringUtils;

{ $define DEBUG_CACHE}

constructor TImagesVideosCache.Create;
begin
  inherited;
  CachedVideos := TCachedVideoList.Create;
end;

destructor TImagesVideosCache.Destroy;
begin
  if CachedVideos <> nil then
  begin
    Assert(CachedVideos.Count = 0, ' Some references to videos still exist ' +
      'when freeing TImagesVideosCache');
    FreeAndNil(CachedVideos);
  end;
  inherited;
end;

function TImagesVideosCache.Video_IncReference(const FileName: string): TVideo;
var
  I: Integer;
  C: TCachedVideo;
begin
  for I := 0 to CachedVideos.Count - 1 do
  begin
    C := CachedVideos[I];
    if C.FileName = FileName then
    begin
      Inc(C.References);

      {$ifdef DEBUG_CACHE}
      Writeln('++ : video ', FileName, ' : ', C.References);
      {$endif}

      Exit(C.Video);
    end;
  end;

  { Initialize Result first, before calling CachedVideos.Add.
    That's because in case TVideo.LoadFromFile raises exception,
    we don't want to add video to cache (because caller would have
    no way to call Video_DecReference later). }

  Result := TVideo.Create;
  try
    Result.LoadFromFile(FileName);
  except
    FreeAndNil(Result);
    raise;
  end;

  C := TCachedVideo.Create;
  CachedVideos.Add(C);
  C.References := 1;
  C.FileName := FileName;
  C.Video := Result;

  {$ifdef DEBUG_CACHE}
  Writeln('++ : video ', FileName, ' : ', 1);
  {$endif}
end;

procedure TImagesVideosCache.Video_DecReference(var Video: TVideo);
var
  I: Integer;
  C: TCachedVideo;
begin
  for I := 0 to CachedVideos.Count - 1 do
  begin
    C := CachedVideos[I];
    if C.Video = Video then
    begin
      {$ifdef DEBUG_CACHE}
      Writeln('-- : video ', C.FileName, ' : ', C.References - 1);
      {$endif}

      Video := nil;

      if C.References = 1 then
      begin
        FreeAndNil(C.Video);
        CachedVideos.Delete(I);
        CheckEmpty;
      end else
        Dec(C.References);

      Exit;
    end;
  end;

  raise EInternalError.CreateFmt(
    'TImagesVideosCache.Video_DecReference: no reference found for video %s',
    [PointerToStr(Video)]);
end;

function TImagesVideosCache.Empty: boolean;
begin
  Result := (inherited Empty) and (CachedVideos.Count = 0);
end;

end.
