{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE Rank2Types #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE RecursiveDo #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeApplications #-}
module Main ( main ) where

import Reflex.Dom
import Reflex.Dom.Widget.Animation (resizeEvents, viewPortSizeI)
import Numeric.DataFrame
import qualified Data.Dependent.Map as DMap

import Commons


import qualified Model.Camera           as Model

import           Widgets.Generation
import qualified Widgets.LoadingSplash  as Widgets
import qualified Widgets.Canvas         as Widgets
import qualified Widgets.ControlPanel   as Widgets
import qualified Widgets.Tabs.Geometry  as Widgets

import qualified SmallGL
import qualified Workers.LoadGeometry as Workers

main :: IO ()
main = mainWidgetInElementById "qua-view-widgets" $ mdo
    -- Change the state of the program
    (isProgramBusy, setIsProgramBusy) <- newTriggerEvent

    -- register loading splash so that we can change its visibility
    Widgets.loadingSplashD isProgramBusy

    -- register canvas element
    canvas <- Widgets.getWebGLCanvas

    -- add the control panel to the page
    (resetCameraE, _panelStateD, geomTabEvs, loggerFunc)
        <- flip runReaderT loggerFunc $ Widgets.controlPanel compStateEvs

    -- initialize web workers
    loadedGeometryE <- Workers.runLoadGeometryWorker $ -- I would need to add other loaded geom events here
        select geomTabEvs Widgets.GeomOutUserLoadsGeomFile
    performEvent_ $ ( \m -> runReaderT
                        ( logInfo' @JSString "main" "Got this back:" m
                        ) loggerFunc
                    ) <$> loadedGeometryE

    -- initialize WebGL rendering context
    let smallGLESel :: forall t a . Reflex t => SmallGL.SmallGLInput a -> Event t a
        smallGLESel SmallGL.ViewPortResize = resizeEvents aHandler
        smallGLESel SmallGL.ProjTransformChange = SmallGL.ProjM . Model.projMatrix <$> updated cameraD
        smallGLESel SmallGL.ViewTransformChange = SmallGL.ViewM . Model.viewMatrix <$> updated cameraD

        -- here we can put various events that enable/disable various components
        compStateEvs = fan . merge $ DMap.fromList
           [ byCompName @"Hello" :=> never
           , byCompName @"Wold"  :=> never
           ]

    renderingApi <- SmallGL.createRenderingEngine canvas (EventSelector smallGLESel)
    -- initialize animation handler (and all pointer events).
    aHandler <- Widgets.registerAnimationHandler canvas (SmallGL.render renderingApi)
    -- supply animation events to camera
    let icamera = Model.initCamera (realToFrac . fst $ viewPortSizeI aHandler)
                                   (realToFrac . snd $ viewPortSizeI aHandler)
                                   Model.CState { Model.viewPoint  = vec3 (-2) 3 0
                                                , Model.viewAngles = (2.745, 0.825)
                                                , Model.viewDist = 68 }
    cameraD <- Model.dynamicCamera icamera aHandler resetCameraE


    -- Notify everyone that the program h finished starting up now
    mainBuilt <- getPostBuild
    performEvent_ . flip fmap mainBuilt . const $ do
        liftIO (setIsProgramBusy Idle)
        Widgets.play aHandler




-- | Create a global css splice.
--   Do not abuse this!
$(do
  qcss
    [cassius|
      body
        position: fixed
        left: 0
        top: 0
        padding: 0
        margin: 0
        width: 100%
        height: 100%
        overflow: hidden
        background-color: #FFFFFF
        touch-action: none
        color: #BF360C

      #qua-view-widgets
        position: fixed
        left: 0
        top: 0
        padding: 0
        margin: 0
        z-index: 1
        overflow: visible
        width: 0
        height: 0
    |]
  return []
 )