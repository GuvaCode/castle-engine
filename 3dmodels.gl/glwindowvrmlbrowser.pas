{
  Copyright 2008 Michalis Kamburelis.

  This file is part of "Kambi VRML game engine".

  "Kambi VRML game engine" is free software; you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation; either version 2 of the License, or
  (at your option) any later version.

  "Kambi VRML game engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with "Kambi VRML game engine"; if not, write to the Free Software
  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

  ----------------------------------------------------------------------------
}

{ TGLWindowVRMLBrowser class, simple VRML browser in a single
  TGLWindow window. }
unit GLWindowVRMLBrowser;

{ This is the weak point of our engine right now: updating octree on changes
  of geometry. It takes some time, as we currently just rebuild the octree.
  On the other hand, it's needed to perform collision detection
  (this also includes picking touch sensors and such) on the up-to-date
  model (in case e.g. touch sensor geometry moves). In some rare
  cases (more precisely: when TVRMLScene.ChangedFields is not optimized
  for this particular field and falls back to TVRMLScene.ChangedAll)
  not updating octree may even cause the octree pointers to be invalid.

  Both problems are being worked on. In the meantime
  - you can define REBUILD_OCTREE to have always accurate and stable
    collision detection, at the expense of a slowdowns in case of intensive
    animations.
  - you can undefine REBUILD_OCTREE to always use the first octree.
    This makes collision detection work with the original geometry,
    and sometimes may make it unstable. OTOH, all works fast. }
{$define REBUILD_OCTREE}

interface

uses VectorMath, GLWindow, VRMLNodes, VRMLGLScene, VRMLScene, Navigation,
  VRMLGLHeadLight;

type
  { A simple VRML browser in a window. This manages TVRMLGLScene,
    navigator (automatically adjusted to NavigationInfo.type) and octrees.
    You simply call @link(Load) method and all is done.

    This class tries to be a thin (not really "opaque")
    wrapper around Scene / Navigator objects. Which means that
    you can access many functionality by directly accessing
    Scene or Navigator objects methods/properties.
    In particular you're permitted to access and call:

    @unorderedList(
      @item(@link(TVRMLScene.ProcessEvents Scene.ProcessEvents))
      @item(@link(TVRMLScene.RegisterCompiledScript Scene.RegisterCompiledScript))
      @item(@link(TVRMLScene.LogChanges Scene.LogChanges))
      @item(Changing VRML graph:

        You can freely change @link(TVRMLScene.RootNode Scene.RootNode)
        contents, provided that you call appropriate Scene.ChangedXxx method.

        You can also freely call events on the VRML nodes.

        You can access BackgroundStack and other stacks.)

      @item(Automatically managed Scene properties, like
        @link(TVRMLScene.BoundingBox Scene.BoundingBox),
        @link(TVRMLScene.TrianglesList Scene.TrianglesList),
        @link(TVRMLScene.ManifoldEdges Scene.ManifoldEdges),
        @link(TVRMLScene.ManifoldEdges Scene.BorderEdges)
        are also free to use.)

      @item(You can also change @link(TVRMLGLScene.Optimization
        Scene.Optimization). You can also change rendering attributes
        by @link(TVRMLGLScene.Attributes Scene.Attributes).)
    )

    Some important things that you @italic(cannot) mess with:

    @unorderedList(
      @item(Don't create/free octrees in Scene.DefaultTriangleOctree,
        Scene.DefaultShapeStateOctree. This class manages them completely.)
      @item(Don't create/free Scene, Navigator and such objects yourself.
        This class manages them, they are always non-nil.)
    )

    This is very simple to use, but note that for more advanced uses
    you're not really expected to extend this class. Instead, you can
    implement something more suitable for you using your own
    TVRMLGLScene, navigator and octrees management.
    In other words, remember that this class just provides
    a simple "glue" between the key components of our engine.
    For specialized cases, more complex scenarios may be needed.

    If you're looking for Lazarus component that does basically the same
    (easy VRML browser), you want to check out TKamVRMLBrowser
    (file @code(../packages/components/kambivrmlbrowser.pas)). }
  TGLWindowVRMLBrowser = class(TGLWindowNavigated)
  private
    FScene: TVRMLGLScene;

    CameraRadius: Single;

    AngleOfViewX, AngleOfViewY: Single;

    function MoveAllowed(ANavigator: TWalkNavigator;
      const ProposedNewPos: TVector3Single; out NewPos: TVector3Single;
      const BecauseOfGravity: boolean): boolean;
    procedure GetCameraHeight(ANavigator: TWalkNavigator;
      out IsAboveTheGround: boolean; out SqrHeightAboveTheGround: Single);

    procedure ScenePostRedisplay(Scene: TVRMLScene);
    procedure MatrixChanged(ANavigator: TNavigator);
    procedure BoundViewpointChanged(Scene: TVRMLScene);
    procedure BoundViewpointVectorsChanged(Scene: TVRMLScene);
    procedure GeometryChanged(Scene: TVRMLScene);
  public
    constructor Create;
    destructor Destroy; override;

    { Creates new @link(Scene), with new navigator and such. }
    procedure Load(const SceneFileName: string);
    procedure Load(ARootNode: TVRMLNode; const OwnsRootNode: boolean);

    property Scene: TVRMLGLScene read FScene;

    procedure EventBeforeDraw; override;
    procedure EventDraw; override;
    procedure EventInit; override;
    procedure EventClose; override;
    procedure EventIdle; override;
    procedure EventResize; override;
    procedure EventMouseDown(Btn: TMouseButton); override;
    procedure EventMouseUp(Btn: TMouseButton); override;
    procedure EventMouseMove(NewX, NewY: Integer); override;
    procedure EventKeyDown(Key: TKey; C: char); override;
    procedure EventKeyUp(Key: TKey); override;
  end;

implementation

uses Boxes3d, VRMLOpenGLRenderer, GL, GLU,
  KambiClassUtils, KambiUtils, SysUtils, Classes, Object3dAsVRML,
  KambiGLUtils, KambiFilesUtils, VRMLTriangleOctree,
  RaysWindow, BackgroundGL;

constructor TGLWindowVRMLBrowser.Create;
begin
  inherited;

  { we manage Navigator ourselves, this makes code more consequent to follow }
  OwnsNavigator := false;

  Load(nil, true);
end;

destructor TGLWindowVRMLBrowser.Destroy;
begin
  FreeAndNil(Scene);
  Navigator.Free;
  Navigator := nil;
  inherited;
end;

procedure TGLWindowVRMLBrowser.Load(const SceneFileName: string);
begin
  Load(LoadAsVRML(SceneFileName, false), true);
end;

procedure TGLWindowVRMLBrowser.Load(ARootNode: TVRMLNode; const OwnsRootNode: boolean);
begin
  FreeAndNil(Scene);
  Navigator.Free;
  Navigator := nil;

  FScene := TVRMLGLScene.Create(ARootNode, OwnsRootNode, roSeparateShapeStates);

  { build octrees }
  Scene.DefaultTriangleOctree :=
    Scene.CreateTriangleOctree('Building triangle octree');
  Scene.DefaultShapeStateOctree :=
    Scene.CreateShapeStateOctree('Building ShapeState octree');

  { init Navigator }
  Navigator := Scene.CreateNavigator(CameraRadius);
  Navigator.OnMatrixChanged := @MatrixChanged;

  if Navigator is TWalkNavigator then
  begin
    WalkNav.OnMoveAllowed := @MoveAllowed;
    WalkNav.OnGetCameraHeight := @GetCameraHeight;
  end;

  { prepare for events procesing (although we let the decision whether
    to turn ProcessEvent := true to the caller). }
  Scene.ResetWorldTimeAtLoad;
  Scene.OnPostRedisplay := @ScenePostRedisplay;
  Scene.OnBoundViewpointVectorsChanged := @BoundViewpointVectorsChanged;
  Scene.ViewpointStack.OnBoundChanged := @BoundViewpointChanged;
  Scene.OnGeometryChanged := @GeometryChanged;

  { allow the scene to use it's own lights }
  Scene.Attributes.UseLights := true;
  Scene.Attributes.FirstGLFreeLight := 1;

  if not Closed then
  begin
    EventResize;
    PostRedisplay;
  end;
end;

procedure TGLWindowVRMLBrowser.EventBeforeDraw;
begin
  inherited;
  Scene.PrepareRender([tgAll], [prBackground, prBoundingBox]);
end;

procedure TGLWindowVRMLBrowser.EventDraw;
begin
  inherited;

  if Scene.Background <> nil then
  begin
    glLoadMatrix(Navigator.RotationOnlyMatrix);
    Scene.Background.Render;
    glClear(GL_DEPTH_BUFFER_BIT);
  end else
    glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT);

  TVRMLGLHeadlight.RenderOrDisable(Scene.Headlight, 0);

  glLoadMatrix(Navigator.Matrix);
  if Navigator is TWalkNavigator then
    Scene.RenderFrustumOctree(WalkNav.Frustum, tgAll) else
    Scene.Render(nil, tgAll);
end;

procedure TGLWindowVRMLBrowser.EventInit;
begin
  inherited;
  glEnable(GL_LIGHTING);
end;

procedure TGLWindowVRMLBrowser.EventClose;
begin
  { This may be called in case of some exceptions, so we better we prepared
    for Scene = nil case. }
  if Scene <> nil then
    Scene.CloseGL;

  inherited;
end;

procedure TGLWindowVRMLBrowser.EventIdle;
begin
  inherited;
  Scene.IncreaseWorldTime(IdleSpeed);
end;

procedure TGLWindowVRMLBrowser.EventResize;
begin
  inherited;
  Scene.GLProjection(Navigator, Scene.BoundingBox, CameraRadius,
    Width, Height, AngleOfViewX, AngleOfViewY);
end;

procedure TGLWindowVRMLBrowser.EventMouseDown(Btn: TMouseButton);
begin
  inherited;
  if Btn = mbLeft then
    Scene.PointingDeviceActive := true;
end;

procedure TGLWindowVRMLBrowser.EventMouseUp(Btn: TMouseButton);
begin
  inherited;
  if Btn = mbLeft then
    Scene.PointingDeviceActive := false;
end;

procedure TGLWindowVRMLBrowser.EventMouseMove(NewX, NewY: Integer);
var
  Ray0, RayVector: TVector3Single;
  OverPoint: TVector3Single;
  Item: POctreeItem;
  ItemIndex: Integer;

  function SensorsCount: Cardinal;
  begin
    if Scene.PointingDeviceSensors <> nil then
      Result := Scene.PointingDeviceSensors.Count else
      Result := 0;
    if Scene.PointingDeviceActiveSensor <> nil then
      Inc(Result);
  end;

begin
  inherited;

  if (Scene.DefaultTriangleOctree <> nil) and
     (Navigator is TWalkNavigator) then
  begin
    Ray(NewX, NewY, AngleOfViewX, AngleOfViewY, Ray0, RayVector);

    ItemIndex := Scene.DefaultTriangleOctree.RayCollision(
      OverPoint, Ray0, RayVector, true, NoItemIndex, false, nil);

    if ItemIndex = NoItemIndex then
      Item := nil else
      Item := Scene.DefaultTriangleOctree.OctreeItems.Pointers[ItemIndex];

    Scene.PointingDeviceMove(OverPoint, Item);

    { I want to keep assertion that CursorNonMouseLook = gcHand when
      we're over or keeping active some pointing-device sensors. }
    if SensorsCount <> 0 then
      CursorNonMouseLook := gcHand else
      CursorNonMouseLook := gcDefault;
  end;
end;

procedure TGLWindowVRMLBrowser.EventKeyDown(Key: TKey; C: char);
begin
  inherited;
  Scene.KeyDown(Key, C, @KeysDown);
end;

procedure TGLWindowVRMLBrowser.EventKeyUp(Key: TKey);
begin
  inherited;
  Scene.KeyUp(Key, #0 { TODO });
end;

function TGLWindowVRMLBrowser.MoveAllowed(ANavigator: TWalkNavigator;
  const ProposedNewPos: TVector3Single; out NewPos: TVector3Single;
  const BecauseOfGravity: boolean): boolean;
begin
  Result := Scene.DefaultTriangleOctree.MoveAllowed(
    ANavigator.CameraPos, ProposedNewPos, NewPos, CameraRadius,
    { Don't let user to fall outside of the box because of gravity. }
    BecauseOfGravity);
end;

procedure TGLWindowVRMLBrowser.GetCameraHeight(ANavigator: TWalkNavigator;
  out IsAboveTheGround: boolean; out SqrHeightAboveTheGround: Single);
var
  GroundItemIndex: Integer;
begin
  Scene.DefaultTriangleOctree.GetCameraHeight(
    ANavigator.CameraPos,
    ANavigator.GravityUp,
    IsAboveTheGround, SqrHeightAboveTheGround, GroundItemIndex,
    NoItemIndex, nil);
end;

procedure TGLWindowVRMLBrowser.ScenePostRedisplay(Scene: TVRMLScene);
begin
  PostRedisplay;
end;

procedure TGLWindowVRMLBrowser.MatrixChanged(ANavigator: TNavigator);
begin
  { Navigator.OnMatrixChanged callback is initialized in constructor
    before Scene is initialized. So to be on the safest side, we check
    here Scene <> nil. }

  if (Scene <> nil) and
     (Navigator is TWalkNavigator) then
    Scene.ViewerPositionChanged(WalkNav.CameraPos);
  PostRedisplay;
end;

procedure TGLWindowVRMLBrowser.BoundViewpointChanged(Scene: TVRMLScene);
begin
  Scene.NavigatorBindToViewpoint(Navigator, CameraRadius, false);
end;

procedure TGLWindowVRMLBrowser.BoundViewpointVectorsChanged(Scene: TVRMLScene);
begin
  Scene.NavigatorBindToViewpoint(Navigator, CameraRadius, true);
end;

procedure TGLWindowVRMLBrowser.GeometryChanged(Scene: TVRMLScene);
begin
{$ifdef REBUILD_OCTREE}
  Scene.PointingDeviceClear;
  CursorNonMouseLook := gcDefault;

  Scene.DefaultTriangleOctree.Free;
  Scene.DefaultShapeStateOctree.Free;

  Scene.DefaultTriangleOctree :=
    Scene.CreateTriangleOctree('Building triangle octree');
  Scene.DefaultShapeStateOctree :=
    Scene.CreateShapeStateOctree('Building ShapeState octree');
{$endif REBUILD_OCTREE}
end;

end.
