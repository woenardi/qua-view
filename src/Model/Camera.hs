{-# LANGUAGE FlexibleContexts, ViewPatterns, DataKinds #-}

module Model.Camera
    ( Camera (..)
    , viewMatrix
    , CState (..)
    , initCamera
    , scroll, dragHorizontal, dragVertical, rotateCentered, twoFingerControl
    , dragObject, rotateObject, twoFingerObject
    , cameraBehavior
    , ObjectTransform (..), objectTransformEvents
    ) where

import Data.Fixed (mod')

import Reflex.Dom.Widget.Animation as Animation
import JavaScript.WebGL

import Numeric.DataFrame
import Numeric.Dimensions

import Commons


----------------------------------------------------------------------------------------------
-- Definitions -------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------
--
---- | Reactive-banana-like camera behavior
--cameraBehavior :: MonadMoment m
--               => Camera -- ^ initial camera
--               -> Event PointerEvent -- ^ pointer actions
--               -> Event WheelEvent -- ^ wheel
--               -> Event ResizeEvent -- ^ resize
--               -> Event () -- ^ reset camera
--               -> Behavior Int -- ^ buttons
--               -> Behavior [(Vec2f, Vec2f)] -- ^ [(old, new)] coordinates
--               -> Behavior Bool -- ^ allow to move camera (is there object dragging or not)
--               -> m (Behavior Camera)
--cameraBehavior cam pointerE wheelE resizeE resetCamE buttonsB coordsB alowMoveB = accumB cam events
--  where
--    events = whenE alowMoveB
--           $ unions [ wheelT <$> wheelE
--                    , pointerT <$> buttonsB <*> coordsB <@> pointerE
--                    , resizeT <$> resizeE
--                    , resetCamT <$> resetCamE
--                    ]
--    -- Modify camera with will zooming
--    wheelT :: WheelEvent -> Camera -> Camera
--    wheelT WheelUp = scroll (-0.1)
--    wheelT WheelDown = scroll 0.15
--    -- Modify camera according to viewport changes
--    resizeT :: ResizeEvent -> Camera -> Camera
--    resizeT (ResizeEvent e) c = initCamera (realToFrac $ coordX e) (realToFrac $ coordY e) (newState c)
--    resetCamT :: () -> Camera -> Camera
--    resetCamT _ c = c{ newState = newState cam, oldState = oldState cam }
--    pointerT :: Int -> [(Vec2f, Vec2f)] -> PointerEvent -> Camera -> Camera
--    -- freeze camera state on pointer up
--    pointerT _ _ (PointerClick  _) c@Camera{ newState = nstate} = c{oldState = nstate}
--    -- freeze camera state on pointer up
--    pointerT _ _ (PointerUp     _) c@Camera{ newState = nstate} = c{oldState = nstate}
--    -- freeze camera state on pointer cancel
--    pointerT _ _ (PointerCancel _) c@Camera{ newState = nstate} = c{oldState = nstate}
--    -- freeze camera state on pointer down
--    pointerT _ _ (PointerDown _) c@Camera{ newState = nstate} = c{oldState = nstate}
--    -- move unknown move (should not happen anyway)
--    pointerT _ [] (PointerMove _) c = c
--    -- Three-finger rotation
--    pointerT 1 ((o1,n1):_:_:_)  (PointerMove _) c = rotateCentered o1 n1 c
--    -- Complicated two-finger control
--    pointerT 1 [(o1,n1),(o2,n2)] (PointerMove _) c = twoFingerControl (o1,o2) (n1,n2) c
--    -- Mouse control                               -- do nothing if no button pressed
--    pointerT b ((opos,npos):_) (PointerMove _) c | b == 0 = c
--                                                   -- Drag horizontally using left mouse button
--                                                 | b == 1 = dragHorizontal opos npos c
--                                                   -- Rotating using secondary button (right m b)
--                                                 | b == 2 = rotateCentered opos npos c
--                                                   -- Dragging vertically using wheel button press
--                                                 | b == 4 = dragVertical opos npos c
--                                                   -- fallback to horizontal dragging
--                                                 | otherwise = dragHorizontal opos npos c
--
--
--
--data (SpaceTransform s 3 Float, Space3DTransform s Float QFloat) =>
--  ObjectTransform s x
--  = ObjectTransform   (s x -> s x)
--  | TransformProgress (s x -> s x)
--  | TransformCancel
--
--
--objectTransformEvents :: ( SpaceTransform s 3 Float
--                         , Space3DTransform s Float QFloat)
--                      => Event PointerEvent -- ^ pointer actions
--                      -> Behavior Int -- ^ buttons
--                      -> Behavior [(Vec2f, Vec2f)] -- ^ [(old, new)] coordinates
--                      -> Behavior Camera
--                      -> Event (ObjectTransform s x)
--objectTransformEvents pointerE buttonsB coordsB cameraB =
--    filterJust $ f <$> cameraB <*> buttonsB <*> coordsB <@> pointerE
--  where
--    f _ _ [] _ = Nothing -- early stop if no pointers found
--    f _ 0 _  _ = Nothing -- early stop if no button pressed
--    f _ _ _ (PointerClick  _) = Just TransformCancel
--    f _ _ _ (PointerDown   _) = Just TransformCancel
----    f _ _ _ (PointerCancel _) = Just TransformCancel
--    -- move & rotate with two fingers pressed
--    f cam _ ((o1,n1):(o2,n2):_) p  = Just . g p $ twoFingerObject (o1,o2) (n1,n2) cam
--    -- rotate object with secondary button
--    f cam 2 ((opos,npos):_) p = Just . g p $ rotateObject opos npos cam
--    -- drag object with any other button
--    f cam _ [(opos,npos)] p = Just . g p $ dragObject opos npos cam
--    g (PointerClick  _) _ = TransformCancel
--    g (PointerDown  _) _ = TransformCancel
--    g (PointerCancel  _) v = ObjectTransform v
--    g (PointerMove  _) v = TransformProgress v
--    g (PointerUp  _) v = ObjectTransform v
--
----    react _ (PMove _            _ []             )   = id
----    react _ (PMove LeftButton   _ ((npos,opos):_))   = transformCity (dragObject opos npos)
----    react _ (PMove RightButton  _ ((npos,opos):_))   = transformCity (rotateObject opos npos)
----    react _ (PMove Touches      _ [(npos,opos)]  )   = transformCity (dragObject opos npos)
----    react _ (PMove Touches      _ [(n1,o1),(n2,o2)]) = transformCity (twoFingerObject (o1,o2) (n1,n2))
----    react _ (PMove Touches      _ (_:_:_:_))         = id
----    react _ (PMove MiddleButton _ _)                 = id
----    response _ _ (PMove _            _ []             )       _ = geometryChanged False
----    response _ _ (PMove LeftButton   _ ((_npos,_opos):_))     _ = geometryChanged True
----    response _ _ (PMove RightButton  _ ((_npos,_opos):_))     _ = geometryChanged True
----    response _ _ (PMove Touches      _ [(_npos,_opos)]  )     _ = geometryChanged True
----    response _ _ (PMove Touches      _ [(_n1,_o1),(_n2,_o2)]) _ = geometryChanged True
----    response _ _ (PMove Touches      _ (_:_:_:_))             _ = geometryChanged False
----    response _ _ (PMove MiddleButton _ _)                     _ = geometryChanged False
--

----------------------------------------------------------------------------------------------
-- Definitions -------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------

-- | Object-Centered Camera
data Camera = Camera
    { viewportSize :: !(Float, Float)
    , projMatrix   :: !Mat44f
    , oldState     :: !CState
    , newState     :: !CState
    } deriving Show


viewMatrix :: Camera -> Mat44f
viewMatrix = stateToView . newState


-- | State of the Camera
data CState = CState {
        viewPoint     :: !Vec3f,
        viewAngles    :: !(Float, Float),
        viewDist      :: !Float
    } deriving Show

-- | Create camera
initCamera :: Float -- ^ width of the viewport
           -> Float -- ^ height of the viewport
           -> CState -- ^ look position and direction
           -> Camera
initCamera width height state = Camera
    { viewportSize = (width,height)
    , projMatrix   = perspectiveM 0.1 1000 fovy ratio
    , oldState     = state
    , newState     = state
    } where ratio = width / height
            fovy = (1*) . atan2 height . sqrt $ height*height + width*width



----------------------------------------------------------------------------------------------
-- Camera convertions ------------------------------------------------------------------------
----------------------------------------------------------------------------------------------

-- | Create view matrix out of camera state
stateToView :: CState -> Mat44f
stateToView CState {
        viewPoint  = v,
        viewAngles = (φ, theta),
        viewDist   = ρ
    } = lookAtMatrix (vector3 0 0 1) (v + dv) v
        where dv = vector3 (t * cos φ) (t * sin φ)  (ρ * sin theta)
              t = ρ * cos theta

----------------------------------------------------------------------------------------------
-- Camera movement functions -----------------------------------------------------------------
----------------------------------------------------------------------------------------------

-- | Dragging - pan world on xz plane (e.g. using left mouse button)
dragHorizontal :: Vec2f -- ^ Old screen coordinates
               -> Vec2f -- ^ New screen coordinates
               -> Camera -- ^ Modify the camera state
               -> Camera
dragHorizontal (unpackV2 -> (ox,oy) ) (unpackV2 -> (x,y)) camera@Camera {
        viewportSize = (width, height),
        projMatrix = projmat,
        oldState   = ostate@CState {
            viewPoint = v@(indexVector 2 -> pz)
        }
    } = camera {
        newState = ostate {
            viewPoint = v + dv
        }
    } where imat = inverse (projmat %* stateToView ostate)
            campos = fromHom $ imat %* vec4 0 0 0 1
            oldpos = fromHom $ imat %* vec4
                (2 * ox / width - 1)
                (1 - 2 * oy / height) 1 1
            newpos = fromHom $ imat %* vec4
                (2 * x / width - 1)
                (1 - 2 * y / height) 1 1
            oldPoint = findPos campos (oldpos - campos) pz
            newPoint = findPos campos (newpos - campos) pz
            dv = oldPoint - newPoint

-- | Dragging - pan world on xy plane
dragVertical :: Vec2f -- ^ Old screen coordinates
             -> Vec2f -- ^ New screen coordinates
             -> Camera -- ^ Modify the camera state
             -> Camera
dragVertical (unpackV2 -> (ox,oy) ) (unpackV2 -> (x,y)) camera@Camera {
        viewportSize = (width, height),
        projMatrix = projmat,
        oldState   = ostate@CState {
            viewPoint = v,
            viewDist  = ρ
        }
    } = camera {
        newState = ostate {
            viewPoint = v + dv
        }
    } where imat = inverse (projmat %* stateToView ostate) :: Mat44f
            sdx = ρ * (x-ox) / width
            dz = ρ * (y-oy) / height
            (dx, dy, _) = unpackV3 $ broadcastVector sdx *
                (unit . resizeVector $ imat %* vec4 (-1) 0 0 0 )-- 0 0 1 1 - imat %* vec4 1 0 1 1)
            dv = vector3 dx dy dz


-- | Rotating around viewPoint
rotateCentered :: Vec2f -- ^ Old screen coordinates
               -> Vec2f -- ^ New screen coordinates
               -> Camera -- ^ Modify the camera state
               -> Camera
rotateCentered (unpackV2 -> (ox,oy) ) (unpackV2 -> (x,y)) camera@Camera {
        viewportSize = (width, height),
        oldState   = ostate@CState {
            viewAngles = (φ, theta)
        }
    } = camera {
        newState = ostate {
            viewAngles = (φ', theta')
        }
    } where dφ = 2*pi*(ox-x) / width
            dtheta = pi*(y-oy) / height
            φ' = mod' (φ+dφ+pi) (2*pi) - pi
            theta' = max (-0.35*pi) . min (0.45*pi) $ theta + dtheta

-- | Scroll camera in and out
scroll :: Float -- ^ Scrolling amout in fractions (i.e. `dist := dist*(1+x)`)
       -> Camera -- ^ Modify the camera state
       -> Camera
scroll s camera@Camera {
        newState = ostate@CState { viewDist = ρ }
    } = camera {
        newState = nstate,
        oldState = nstate
    } where nstate = ostate { viewDist = max 0.1 (ρ * (1 + min (8 / (1 + ρ)) (max (max (-0.8) (- 8 / (1 + ρ))) s))) }

-- | Rotate, scale, and pan with two fingers
twoFingerControl :: (Vec2f, Vec2f) -- ^ Old screen coordinates
                 -> (Vec2f, Vec2f) -- ^ New screen coordinates
                 -> Camera -- ^ Modify the camera state
                 -> Camera
twoFingerControl (unpackV2 -> (opx1,opy1),unpackV2 -> (opx2,opy2))
                 (unpackV2 -> (npx1,npy1),unpackV2 -> (npx2,npy2))
                 camera@Camera {
                    viewportSize = (width, height),
                    projMatrix   = projmat,
                    oldState     = ostate@CState {
                        viewPoint  = ovp@(indexVector 2 -> h),
                        viewAngles = (φ, theta),
                        viewDist   = ρ
                    }
    } = camera {
        newState = ostate {
            viewPoint  = nvp, -- ovp + dvp,
            viewAngles = (φ', theta),
            viewDist   = max 0.1 (ρ*dlen)
        }
    } where imat = inverse $ projmat %* stateToView ostate
            screenO1 = vec4 (2 * opx1 / width - 1) (1 - 2 * opy1 / height) 1 1
            screenO2 = vec4 (2 * opx2 / width - 1) (1 - 2 * opy2 / height) 1 1
            screenN1 = vec4 (2 * npx1 / width - 1) (1 - 2 * npy1 / height) 1 1
            screenN2 = vec4 (2 * npx2 / width - 1) (1 - 2 * npy2 / height) 1 1
            up = vector3 0 0 1
            campos = fromHom $ imat %* vec4 0 0 0 1
            realO1 = findPos campos (fromHom (imat %* screenO1) - campos) h
            realO2 = findPos campos (fromHom (imat %* screenO2) - campos) h
            realN1 = findPos campos (fromHom (imat %* screenN1) - campos) h
            realN2 = findPos campos (fromHom (imat %* screenN2) - campos) h
            dOld = realO2 - realO1
            dNew = realN2 - realN1
            realN = 0.5 * (realN1 + realN2)
            realO = 0.5 * (realO1 + realO2)
            qs = getRotScale dNew dOld
            -- scaling
            dlen = normL2 $ toVec4 qs
--            olen = normL2 dOld
--            nlen = normL2 dNew
--            dlen = if abs (olen/nlen - 1) < 0.05
--                then 1
--                else let dl0 = olen/nlen
--                     in 1 + (dl0 - 1) * min 1 (50 / (1 + ρ)) -- prevent going too far away on large distances
            -- rotating
            dφ = let da = signum (dot up $ imVec qs) * qArg qs -- atan2 (indexVector 2 $ cross dNew dOld) (dot dNew dOld)
                 in if abs da < 0.05 then 0 else da
            φ' = mod' (φ+dφ+pi) (2*pi) - pi
            -- panning
            -- combine actions
            nvp = rotScale qs (ovp - realN) + realO
--            nvp = rotScale (realToFrac dlen * axisRotation up (φ - φ')) (ovp-realN1)
--                  + realO1 -- + 2*newPoint



----------------------------------------------------------------------------------------------
-- Object movement functions -----------------------------------------------------------------
----------------------------------------------------------------------------------------------


-- | Dragging - pan object on xz plane (e.g. using left mouse button)
dragObject :: Vec2f -- ^ Old screen coordinates
           -> Vec2f -- ^ New screen coordinates
           -> Camera -- ^ Get matrices
           -> Mat44f  -- ^ transformation matrix
dragObject (unpackV2 -> (ox,oy) ) (unpackV2 -> (x,y)) camera = ap $ translate dv id
    where imat = inverse (projMatrix camera %* viewMatrix camera)
          (width, height) = viewportSize camera
          campos = fromHom $ imat %* vec4 0 0 0 1
          oldpos = fromHom $ imat %* vec4
                (2 * ox / width - 1)
                (1 - 2 * oy / height) 1 1
          newpos = fromHom $ imat %* vec4
                (2 * x / width - 1)
                (1 - 2 * y / height) 1 1
          oldPoint = findPos campos (oldpos - campos) 0
          newPoint = findPos campos (newpos - campos) 0
          dv = newPoint - oldPoint


-- | Rotating - rotate object on w.r.t. y axis (e.g. using right mouse button)
rotateObject :: Vec2f -- ^ Old screen coordinates
             -> Vec2f -- ^ New screen coordinates
             -> Camera -- ^ Get matrices
             -> Mat44f  -- ^ transformation matrix
rotateObject (unpackV2 -> (ox,oy) ) (unpackV2 -> (x,y)) camera = f
    where imat = inverse (projMatrix camera %* viewMatrix camera)
          (width, height) = viewportSize camera
          campos = fromHom $ imat %* vec4 0 0 0 1
          oldpos = fromHom $ imat %* vec4
                (2 * ox / width - 1)
                (1 - 2 * oy / height) 1 1
          newpos = fromHom $ imat %* vec4
                (2 * x / width - 1)
                (1 - 2 * y / height) 1 1
          oldPoint = findPos campos (oldpos - campos) 0
          newPoint = findPos campos (newpos - campos) 0
          f t = t >>= rotateZ a
                where dv1 = unit $ newPoint - p
                      dv0 = unit $ oldPoint - p
                      p = transform $ wrap 0 t
                      a = atan2 (indexVector 2 $ cross dv0 dv1) (dot dv1 dv0)


-- | Rotate, scale, and pan with two fingers
twoFingerObject :: (Vec2f, Vec2f) -- ^ Old screen coordinates
                -> (Vec2f, Vec2f) -- ^ New screen coordinates
                -> Camera -- ^ Get matrices
                -> Mat44f -- ^ transformation matrix
twoFingerObject (unpackV2 -> (ox1,oy1), unpackV2 -> (ox2,oy2))
                (unpackV2 -> (x1,y1)  , unpackV2 -> (x2,y2)  )
                 camera = f
    where imat = inverse (projMatrix camera %* viewMatrix camera)
          (width, height) = viewportSize camera
          ox = (ox1 + ox2) / 2
          oy = (oy1 + oy2) / 2
          x = (x1 + x2) / 2
          y = (y1 + y2) / 2
          -- rotating
          oangle = atan2 (ox1 - ox2) (oy1 - oy2)
          nangle = atan2 (x1 - x2) (y1 - y2)
          dφ = if abs (nangle-oangle) < 0.05 then 0 else nangle-oangle
          -- panning
          campos = fromHom $ imat %* vec4 0 0 0 1
          oldpos = fromHom $ imat %* vec4
                (2 * ox / width - 1)
                (1 - 2 * oy / height) 1 1
          newpos = fromHom $ imat %* vec4
                (2 * x / width - 1)
                (1 - 2 * y / height) 1 1
          oldPoint = findPos campos (oldpos - campos) 0
          newPoint = findPos campos (newpos - campos) 0
          dv = newPoint - oldPoint
          f t = translate dv id <*> (t >>= rotateZ dφ)

----------------------------------------------------------------------------------------------
-- Helpers  ----------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------

-- | find position of the intersection of a ray traced from camera point to ground
findPos :: Vec3f -- ^ camera position
        -> Vec3f -- ^ camera sight vector
        -> Float -- ^ height level of the point
        -> Vec3f -- ^ position of the point in 3D
findPos (unpackV3 -> (c1, c2, c3)) (unpackV3 -> (v1, v2, v3)) h = vector3 x y h
    where l = (h - c3)/v3'
          x = c1 + v1*l
          y = c2 + v2*l
          v3' = if abs v3 < 0.0000000001 then signum v3 * 0.0000000001 else v3