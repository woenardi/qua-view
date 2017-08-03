{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}

module Widgets.Tabs.Navigator
    ( PanelState (..),
      tabsNavigator
    ) where


import Reflex.Dom
import Commons
import Widgets.Generation

-- | Determining which panel is active
data PanelState = PanelGeometry | PanelInfo | PanelServices
    deriving Eq

tabsNavigator :: Reflex t => Widget x (Dynamic t PanelState)
tabsNavigator = do
  (geometryE, infoE, servicesE) <- elClass "nav" "tab-nav tab-nav-red margin-top-no" $ do
    (gE, iE, sE) <- elClass "ul" "nav nav-justified" $ do
      geometryEl <- makeElementFromHtml def $(qhtml
        [hamlet|
          <li class="active">
            <a aria-expanded="true" class="waves-attach waves-effect" data-toggle="tab" href="#itabGeometry">
              Geometry
        |])
      infoEl <- makeElementFromHtml def $(qhtml
        [hamlet|
          <li class="">
            <a aria-expanded="false" class="waves-attach waves-effect" data-toggle="tab" href="#itabInfo">
              Info
        |])
      servicesEl <- makeElementFromHtml def $(qhtml
        [hamlet|
          <li class="">
            <a aria-expanded="false" class="waves-attach waves-effect" data-toggle="tab" href="#itabServices">
              Services
        |])
      return (domEvent Click geometryEl, domEvent Click infoEl, domEvent Click servicesEl)
    elAttr "div" (("class" =: "tab-nav-indicator") <> ("style" =: "left: 0px; right: 412px;")) blank
    return (gE, iE, sE)
  holdDyn PanelGeometry $ leftmost [PanelGeometry <$ geometryE,
                                    PanelInfo <$ infoE,
                                    PanelServices <$ servicesE]
