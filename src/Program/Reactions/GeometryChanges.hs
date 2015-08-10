{-# LANGUAGE DataKinds, FlexibleInstances, MultiParamTypeClasses #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}
-----------------------------------------------------------------------------
-- |
-- Module      :  Program.Reactions.GeometryChanges
-- Copyright   :  (c) Artem Chirkin
-- License     :  BSD3
--
-- Maintainer  :  Artem Chirkin <chirkin@arch.ethz.ch>
-- Stability   :  experimental
--
--
--
-----------------------------------------------------------------------------

module Program.Reactions.GeometryChanges () where

--import Geometry.Space
--import Geometry.Space.Transform
--import Geometry.Math
import GHCJS.Marshal
import GHCJS.Useful

import Reactive
import Controllers.GUIEvents
import Controllers.LuciClient

import Program
import Program.Model.City
import Program.Model.CityObject
import Program.Model.GeoJSON
import Program.View

--import Debug.Trace
--import Geometry.Structure
--import Control.Monad

updateProgramView :: String -> Program -> PView -> IO (Either PView e)
updateProgramView msg program pview = do
        getElementById "clearbutton" >>= elementParent >>= hideElement
        cityView' <- updateView (glctx $ context pview) (city program) (cityView pview)
        logText msg
--        (toJSRef_aeson . geometries2features . cityGeometryFull3D $ city program) >>= printRef
        programInProgress
        mscenario <- case luciClient pview of
            Nothing -> logText ("I would send new geometry to Luci, but we are not connected :(")
                        >> return Nothing
            Just lc -> do
                tryscenario <- createScenario lc "Visualizer scenario" . geometries2features . cityGeometryRoofs $ city program
                case tryscenario of
                    Left err ->  toJSRef err >>= printRef >> return Nothing
                    Right scenario -> return (Just scenario)
--        (toJSRef_aeson . cityGeometryFull3D $ city program) >>= printRef
        programIdle
        return $ Left pview{cityView = cityView', luciScenario = mscenario}

instance Reaction Program PView ClearingGeometry "Clearing City Geometry" 0 where
    react _ ClearingGeometry program = program
        { city = clearCity (city program)
        , controls = (controls program){placeTransform = Nothing}
        }
    response _ _ = updateProgramView "Cleared geometry."


instance Reaction Program PView GeoJSONLoaded "Updating City Geometry after GeoJSON is loaded" 0 where
    react _ geoJSONI program@Program{controls = c@Controls{placeTransform = Nothing}}
        = program{controls = c{placeTransform = Just (scal, shift)}}
        { city = addCityStaticWires lns $ addCityObjects geoms (city program)
        }
        where ((geoms, lns),_msgs,scal,shift) = featureCollectionToObjectsAndScale
                    behav (featureCollection geoJSONI) -- TODO: how to log this?
              behav = if isDynamic geoJSONI then Dynamic else Static
    react _ geoJSONI program@Program{controls = Controls{placeTransform = Just (scal, shift)}}
        = program
        { city = addCityStaticWires lns $ addCityObjects geoms (city program)
        }
        where ((geoms, lns),_msgs) = featureCollectionToObjects
                    behav scal shift (featureCollection geoJSONI) -- TODO: how to log this?
              behav = if isDynamic geoJSONI then Dynamic else Static
    response _ _ = updateProgramView "Updated geometry."


