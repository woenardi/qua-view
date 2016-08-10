{-# LANGUAGE FlexibleContexts, OverloadedStrings, GeneralizedNewtypeDeriving #-}
{-# LANGUAGE ForeignFunctionInterface,  JavaScriptFFI, GHCForeignImportPrim, UnliftedFFITypes #-}
{-# LANGUAGE DataKinds, FlexibleInstances, MultiParamTypeClasses #-}
-----------------------------------------------------------------------------
-- |
-- Module      :  Program.Controllers.LuciClient
-- Copyright   :  (c) Artem Chirkin
-- License     :  MIT
--
-- Maintainer  :  Artem Chirkin <chirkin@arch.ethz.ch>
-- Stability   :  experimental
--
--
--
-----------------------------------------------------------------------------

module Program.Controllers.LuciClient
    ( -- * Client
      LuciClient (..), luciHandler, connectionString
      -- * Core message types
    , LuciMessage (..), sendMessage
    , msgHeaderValue, toLuciMessage
    , MessageHeader (..)
    , ServiceResult (..)
    , ServiceName (..), unServiceName
      -- * Specific messages
    , LuciResultServiceList (..), runServiceList
    , LuciResultTestFibonacci, runTestFibonacci
    , LuciScenario (..), runScenarioGet, runScenarioUpdate, runScenarioCreate
    , LuciResultScenarioList (..), ScenarioDescription (..), runScenarioList
    , registerAskLuciForScenario, displayScenarios, GUI.registerGetScenarioList
    ) where


import qualified Program.Controllers.GUI as GUI
--import Data.Int (Int64)
--import JsHs.JSString (JSString, append,unpack',pack)

import Data.List (foldl')
import Data.String (IsString)

---- import GHCJS.Foreign
import JsHs
import JsHs.Types.Prim (jsNull)
import JsHs.JSString (unpack')
import Data.Geometry.Structure.Feature (FeatureCollection)
import qualified JsHs.Array as JS
import qualified JsHs.TypedArray as JSTA
import qualified JsHs.Callback as JS (Callback, asyncCallback2, asyncCallback1, asyncCallback)

--import Control.Arrow (first)
import Program.Settings
import Program.Types
import Reactive.Banana.Frameworks
import Reactive.Banana.Combinators
import Reactive.Banana.JsHs.Types (Time)
--import Control.Concurrent (threadDelay, forkIO)
--import Control.Monad (void)
import Data.Maybe (fromMaybe)

import Data.Time
--import Data.Time.Clock (secondsToDiffTime)
import Data.Time.Clock.POSIX (posixSecondsToUTCTime, utcTimeToPOSIXSeconds)

----------------------------------------------------------------------------------------------------
-- * Client
----------------------------------------------------------------------------------------------------


-- | Object for Luci connection
data LuciClient
  = LuciClient JSVal -- ^ ready state
  | LuciClientOpening -- ^ opening connection
  | LuciClientClosed  -- ^ websocket connection closed
  | LuciClientError JSString -- ^ error occured

instance LikeJS "Luci.Client" LuciClient where
  asLikeJS jsv = case asLikeJS $ js_Luci jsv of
                  Nothing -> LuciClientError "Not a valid Luci.Client object"
                  Just l -> LuciClient l
  asJSVal (LuciClient jsv) = jsv
  asJSVal _ = jsNull

foreign import javascript unsafe "($1 && $1.objectName == 'LuciClient') \
                                 \ ? $1 : null" js_Luci :: JSVal -> JSVal


-- | Luci messages - send and receive
data LuciMessage = LuciMessage
  { header      :: !JSString
  , attachments :: !(JS.Array JSTA.ArrayBuffer)
  }

-- | get message header as using JSON.parse()
msgHeaderValue :: LikeJS s a => LuciMessage -> a
msgHeaderValue (LuciMessage h _) = asLikeJS $ jsonParse h

-- | create a message using JSON.stringify()
toLuciMessage :: LikeJS s a => a -> [JSTA.ArrayBuffer] -> LuciMessage
toLuciMessage h bs = LuciMessage (jsonStringify $ asJSVal h) (JS.fromList bs)



-- | Create LuciClient and register events on message receive
luciHandler :: JSString -> MomentIO (Behavior LuciClient, Event LuciClient, Event LuciMessage)
luciHandler str = do
  -- create all handlers
  (connectH, (onMessageH, onMessageFire)
           , (onOpenH, onOpenFire)
           , (onCloseH, onCloseFire)
           , (onErrorH, onErrorFire)
           ) <- liftIO $ do
    -- setup connection form
    GUI.showLuciConnectForm str
    (userClickH, userClickFire) <- newAddHandler
    -- register user click
    GUI.registerUserConnectToLuci userClickFire
    (,,,,) userClickH
            <$> newAddHandler
            <*> newAddHandler
            <*> newAddHandler
            <*> newAddHandler
  -- when user clicked on connect button
  connectE <- fromAddHandler connectH
  -- create Luci Client
  eLuciClientE <- flip mapEventIO connectE $ \url -> newLuciClient url onMessageFire
                          (onOpenFire ())
                          (onCloseFire LuciClientClosed)
                          (onErrorFire . LuciClientError)
  luciMsgs <- fromAddHandler onMessageH

  luciOpenEM <- fmap filterJust
      . flip mapEventIO eLuciClientE
      $ \eLuciClient -> case eLuciClient of
    Left err -> do
      onErrorFire (LuciClientError err)
      return Nothing
    Right lc -> return . Just $ (lc <$) <$> fromAddHandler onOpenH
  luciOpenE <- execute luciOpenEM >>= switchE
  luciCloseE <- fromAddHandler onCloseH
  luciErrorE <- fromAddHandler onErrorH
  let luciE = luciOpenE +*+ luciCloseE +*+ luciErrorE
      (+*+) = unionWith (const id)
  luciB <- stepper LuciClientOpening luciE
  lastUrlB <- stepper str connectE
  reactimate $ GUI.showLuciConnectForm <$> lastUrlB <@ luciCloseE
  reactimate $ GUI.showLuciConnectForm <$> lastUrlB <@ luciErrorE
  reactimate $ GUI.showLuciConnected <$> lastUrlB <@ luciOpenE
  return (luciB, luciE, luciMsgs)


foreign import javascript interruptible "try{$c(new LikeHS.Either(new Luci.Client($1,$2,$3,$4,$5),true));}\
                                        \catch(e){$c(new LikeHS.Either(e['message'] ? e['message'] : 'Luci client initialization error.',false));}"
  js_newLuciClient :: JSString -- ^ Connection string
                   -> JS.Callback (JSVal -> JSVal -> IO ()) -- ^ onmessage
                   -> JS.Callback (IO ()) -- ^ onopen
                   -> JS.Callback (IO ()) -- ^ onclose
                   -> JS.Callback (JSVal -> IO ()) -- ^ onerror
                   -> IO JSVal

-- | Create a new luci instance and connect
newLuciClient :: JSString  -- ^ connection string (i.e. ws://localhost:8080/luci)
              -> (LuciMessage -> IO ()) -- ^ onmessage callback
              -> IO () -- ^ onopen callback
              -> IO () -- ^ onclose callback
              -> (JSString -> IO ()) -- ^ onerror callback
              -> IO (Either JSString LuciClient)
newLuciClient connStr onMsgCall onOpenCall onCloseCall onErrorCall = do
  jsOnMessage <- JS.asyncCallback2 (\h d -> onMsgCall $ LuciMessage (asLikeJS h) (asLikeJS d))
  jsOnOpen <- JS.asyncCallback onOpenCall
  jsOnClose <- JS.asyncCallback onCloseCall
  jsOnError <- JS.asyncCallback1 (onErrorCall . asLikeJS)
  asLikeJS <$> js_newLuciClient connStr jsOnMessage jsOnOpen jsOnClose jsOnError

-- | Full string passed into WebSocket constructor
connectionString :: LuciClient -> JSString
connectionString (LuciClient c) = js_connectionString c
connectionString _ = ""
foreign import javascript safe "$1.connectionString"
  js_connectionString :: JSVal -> JSString

-- | Send Luci message
sendMessage :: LuciClient -> LuciMessage -> IO ()
sendMessage (LuciClient luci) (LuciMessage h a) = js_sendMessage luci h a
sendMessage _ _ = return ()

foreign import javascript safe "$1.sendMessage($2,$3)"
  js_sendMessage :: JSVal -> JSString -> JS.Array JSTA.ArrayBuffer -> IO ()



----------------------------------------------------------------------------------------------------
-- * Message core types
----------------------------------------------------------------------------------------------------

-- | JSON Value representing result of a luci service work
newtype ServiceResult = ServiceResult JSVal
instance LikeJS "Object" ServiceResult

-- | Luci callID is used to reference client's calls to luci and services
newtype CallId = CallId Int
  deriving (Eq,Ord,Show,Enum,Num,Real,Integral)
instance LikeJS "Number" CallId where
  asLikeJS = CallId . asLikeJS
  asJSVal (CallId v) = asJSVal v

-- | Luci taskID is used in the context of luci workflows to refer to tasks
newtype TaskId = TaskId Int
  deriving (Eq,Ord,Show,Enum,Num,Real,Integral)
instance LikeJS "Number" TaskId where
  asLikeJS = TaskId . asLikeJS
  asJSVal (TaskId v) = asJSVal v

-- | Percentage [0..100]%; used in luci messages to indicate state of a service computation
newtype Percentage = Percentage Double
  deriving (Eq,Ord,Num,Real,RealFrac,RealFloat,Fractional,Floating)
instance LikeJS "Number" Percentage where
  asLikeJS = Percentage . asLikeJS
  asJSVal (Percentage v) = asJSVal v
instance Show Percentage where
  show (Percentage x) = show (fromIntegral (round $ x*100 :: Int) / 100 :: Double) ++ "%"

-- | Luci service name
newtype ServiceName = ServiceName JSString
  deriving (Eq,Ord,Show,IsString)
instance LikeJS "String" ServiceName where
  asLikeJS = ServiceName . asLikeJS
  asJSVal (ServiceName v) = asJSVal v

unServiceName :: ServiceName -> String
unServiceName (ServiceName a) = unpack' a

-- | All possible message headers
data MessageHeader
  = MsgRun ServiceName [(JSString, JSVal)]
    -- ^ run service message, e.g. {'run': 'ServiceList'};
    -- params: 'run', [(name, value)]
  | MsgCancel CallId
    -- ^ cancel service message, e.g. {'cancel': 25};
    -- params: 'callID'
  | MsgNewCallID CallId
    -- ^ Luci call id, { newCallID: 57 };
    -- params: 'newCallID'
  | MsgResult CallId Time ServiceName TaskId ServiceResult
    -- ^ result of a service execution,
    -- e.g. { callID: 57, duration: 0, serviceName: "ServiceList", taskID: 0, result: Object };
    -- params: 'callID', 'duration', 'serviceName', 'taskID', 'result'
  | MsgProgress CallId Time ServiceName TaskId Percentage ServiceResult
    -- ^ result of a service execution,
    -- e.g. { callID: 57, duration: 0, serviceName: "St", taskID: 0, percentage: 0, progress: null};
    -- params: 'callID', 'duration', 'serviceName', 'taskID', 'percentage', 'progress'
  | MsgError JSString
    -- ^ error message, e.g. {'error': 'We are in trouble!'};
    -- params: 'error'
  | MsgPanic JSString
    -- ^ Initiate the panic recovery procedure
  | MsgUnknown JSVal
    -- ^ unknown type of message; passed as-is

instance LikeJS "Object" MessageHeader where
  asLikeJS jsv | Just r <- getProp "result"    jsv = maybeUnknown jsv $ MsgResult
                                                   <$> getProp "callID" jsv
                                                   <*> getProp "duration" jsv
                                                   <*> getProp "serviceName" jsv
                                                   <*> getProp "taskID" jsv
                                                   <*> Just r
               | Just e <- getProp "error"     jsv = MsgError e
               | Just i <- getProp "newCallID" jsv = MsgNewCallID i
               | Just r <- getProp "progress"  jsv = maybeUnknown jsv $ MsgProgress
                                                   <$> getProp "callID" jsv
                                                   <*> getProp "duration" jsv
                                                   <*> getProp "serviceName" jsv
                                                   <*> getProp "taskID" jsv
                                                   <*> getProp "percentage" jsv
                                                   <*> Just r
               | Just i <- getProp "cancel"    jsv = MsgCancel i
               | Just p <- getProp "panic"     jsv = MsgPanic p
               | Just n <- getProp "run"       jsv = MsgRun n [] -- TODO: use .getOwnPropertyNames()
               | otherwise = MsgUnknown jsv
    where
      maybeUnknown j Nothing  = MsgUnknown j
      maybeUnknown _ (Just v) = v
  asJSVal (MsgRun run props) = fromProps $ ("run", JS.asJSVal run):props
  asJSVal (MsgCancel callID) = setProp "callID" callID newObj
  asJSVal (MsgNewCallID newCallID) = setProp "newCallID" newCallID newObj
  asJSVal (MsgResult callID duration serviceName taskID result) =
          setProp "callID" callID
        . setProp "duration" duration . setProp "taskID" taskID
        . setProp "serviceName" serviceName $ setProp "result" result newObj
  asJSVal (MsgProgress callID duration serviceName taskID percentage result) =
          setProp "callID" callID
        . setProp "duration" duration . setProp "taskID" taskID . setProp "percentage" percentage
        . setProp "serviceName" serviceName $ setProp "result" result newObj
  asJSVal (MsgError err) = setProp "error" err newObj
  asJSVal (MsgPanic panic) = setProp "panic" panic newObj
  asJSVal (MsgUnknown j) = j


----------------------------------------------------------------------------------------------------
-- * Pre-defined messages
----------------------------------------------------------------------------------------------------

-- | A message to get list of available services from luci
runServiceList :: LuciMessage
runServiceList = toLuciMessage (MsgRun "ServiceList" []) []

newtype LuciResultServiceList = ServiceList (JS.Array JSString)
  deriving (Show)
instance LikeJS "Object" LuciResultServiceList where
  asLikeJS b = case getProp "serviceNames" b of
                 Just x  -> ServiceList x
                 Nothing -> ServiceList JS.emptyArray
  asJSVal (ServiceList v) = setProp "serviceNames" v newObj

-- | run a testing service test.Fibonacci
runTestFibonacci :: Int -> LuciMessage
runTestFibonacci n = toLuciMessage (MsgRun "test.Fibonacci" [("amount", JS.asJSVal n)]) []

newtype LuciResultTestFibonacci = TestFibonacci [Int]
  deriving (Show, Eq)
instance LikeJS "Object" LuciResultTestFibonacci where
  asLikeJS b = case getProp "fibonacci_sequence" b of
                 Just x  -> TestFibonacci $ JS.asLikeJS x
                 Nothing -> TestFibonacci []
  asJSVal (TestFibonacci xs) = setProp "fibonacci_sequence" xs newObj



-- | Luci scenario
data LuciScenario = LuciResultScenario ScenarioId FeatureCollection
instance LikeJS "Object" LuciScenario where
  asLikeJS jsv = case (,) <$> getProp "ScID" jsv <*> getProp "FeatureCollection" jsv of
                  Just (scId, fc) -> LuciResultScenario scId fc
                  Nothing -> LuciResultScenario 0 $ JS.fromJSArray JS.emptyArray
  asJSVal (LuciResultScenario scId fc) =
            setProp "ScID"  (JS.asJSVal scId)
          $ setProp "FeatureCollection" fc newObj

-- | Pass the name of the scenario and a feature collection with geometry
runScenarioCreate :: JSString -- ^ name of the scenario
                  -> FeatureCollection -- ^ content of the scenario
                  -> LuciMessage
runScenarioCreate name collection = toLuciMessage
  ( MsgRun "scenario.geojson.Create"
      [ ("name", JS.asJSVal name)
      , ("geometry_input"
        ,   setProp "format"  ("GeoJSON" :: JSString)
          $ setProp "geometry" collection newObj
        )
      ]
  ) []

runScenarioUpdate :: ScenarioId -- ^ id of the scenario
                  -> FeatureCollection -- ^ content of the scenario update
                  -> LuciMessage
runScenarioUpdate scId collection = toLuciMessage
  ( MsgRun "scenario.geojson.Update"
      [ ("ScID", JS.asJSVal scId)
      , ("geometry_input"
        ,   setProp "format"  ("GeoJSON" :: JSString)
          $ setProp "geometry" collection newObj
        )
      ]
  ) []

runScenarioGet :: ScenarioId -- ^ id of the scenario
               -> LuciMessage
runScenarioGet scId = toLuciMessage
  ( MsgRun "scenario.geojson.Get"
      [ ("ScID", JS.asJSVal scId)
      ]
  ) []


runScenarioList :: LuciMessage
runScenarioList = toLuciMessage  (MsgRun "scenario.GetList" []) []

newtype LuciResultScenarioList = ScenarioList [ScenarioDescription]
  deriving (Show)
instance LikeJS "Object" LuciResultScenarioList where
  asLikeJS b = case getProp "scenarios" b of
                 Just x  -> ScenarioList x
                 Nothing -> ScenarioList []
  asJSVal (ScenarioList v) = setProp "scenarios" v newObj


data ScenarioDescription = ScenarioDescription
  { scCreated  :: UTCTime
  , scModified :: UTCTime
  , scName     :: JSString
  , sscId      :: ScenarioId
  }
  deriving (Eq,Ord,Show)
instance LikeJS "Object" ScenarioDescription where
  asLikeJS jsv = ScenarioDescription
    { scCreated  = f $ getProp "created" jsv
    , scModified = f $ getProp "lastmodified" jsv
    , scName     = fromMaybe "" $ getProp "name" jsv
    , sscId      = fromMaybe (-1) $ getProp "ScID" jsv
    }
      where
        f = posixSecondsToUTCTime . realToFrac . secondsToDiffTime . flip div 1000 . fromMaybe 0
  asJSVal scd =
          setProp "ScID" (sscId scd) . setProp "name" (scName scd)
        . setProp "lastmodified" (f $ scModified scd :: Int) $ setProp "created" (f $ scCreated scd :: Int) newObj
      where
        f = (1000 *) . round . utcTimeToPOSIXSeconds


----------------------------------------------------------------------------------------------------
-- * Qua-server integration
----------------------------------------------------------------------------------------------------

displayScenarios ::  ServiceResult -> IO ()
displayScenarios = GUI.displayScenarios . asJSVal

-- | Registers one callback; comes from Handler.Home.PanelGeometry.
--   h :: ScID -> IO ()
--   return :: IO ()
registerAskLuciForScenario :: (ScenarioId -> JSString -> IO ()) -> IO ()
registerAskLuciForScenario f = GUI.registerAskLuciForScenario (f . ScenarioId)

--
--runLuciService :: LuciClient -> JSString -> LuciServiceInput -> LuciScenario -> IO (Either JSString LuciServiceOutput)
--runLuciService lc service inputs scenario = eitherError "service output" <$>
--                                            runService' lc service (scenarioId scenario) inputs
--foreign import javascript interruptible  "var req = {}; \
--    \ req['run'] = $2; \
--    \ req['ScID'] = $3; \
--    \ req['gridMultiPoint'] = $4; \
--    \ var logg = (DEBUG && console.log('Running Luci service:')); \
--    \ logg = (DEBUG && console.log(req)); \
--    \ $1.sendAndReceive(req, new QLuciHandler($c));"
--    runService' :: LuciClient -> JSString -> Int -> LuciServiceInput -> IO JSVal
--
---- | Get list of names of available services in Luci
--getServicesList :: LuciClient -> IO (Either JSString [JSString])
--getServicesList lc = eitherError "Luci answer" <$> getServicesList' lc
--foreign import javascript interruptible "var req = {}; \
--    \ req['run'] = 'ServiceList'; \
--    \ $1.sendAndReceive(req, new QLuciHandler($c, ['ServiceList']));"
--    getServicesList' :: LuciClient -> IO JSVal
--
--
--getServiceInfo :: LuciClient -> JSString -> IO (Either JSString LuciServiceInfo)
--getServiceInfo lc sname = eitherError "LuciServiceInfo" <$> getServiceInfo' lc sname
--foreign import javascript interruptible "var req = {}; \
--    \ req['run'] = 'ServiceInfo'; \
--    \ req['serviceNames'] = [$2]; \
--    \ $1.sendAndReceive(req, new QLuciHandler($c, [$2]));"
--    getServiceInfo' :: LuciClient -> JSString -> IO JSVal
--
--
--createLuciScenario :: LuciClient -> JSString -> FeatureCollection -> IO (Either JSString LuciScenario)
--createLuciScenario lc sname geom = eitherError "Luci Scenario" <$> createScenario' lc sname geom
--foreign import javascript interruptible "var req = {}; \
--    \ req['run'] = 'scenario.geojson.Create'; req['name'] = $2; \
--    \ req['geometry_input']= {}; \
--    \ req['geometry_input']['name'] = 'geometry_input'; \
--    \ req['geometry_input']['format'] = 'GeoJSON'; \
--    \ req['geometry_input']['geometry'] = $3; \
--    \ $1.sendAndReceive(req,new QLuciHandler($c));"
--    createScenario' :: LuciClient -> JSString -> FeatureCollection -> IO JSVal
--
--eitherError :: LikeJS ta a => JSString -> JSVal -> Either JSString a
--eitherError s val = case asLikeJS val of
--                      Just x -> x
--                      Nothing -> Left $ "Something bad has just happened: " `append` s `append` " is null or undefined."