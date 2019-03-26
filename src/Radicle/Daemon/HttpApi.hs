{-# OPTIONS_GHC -fno-warn-orphans #-}
module Radicle.Daemon.HttpApi
    ( QueryRequest(..)
    , QueryResponse(..)
    , machineQueryEndpoint

    , SendRequest(..)
    , SendResponse(..)
    , machineSendEndpoint

    , NewResponse(..)
    , newMachineEndpoint

    , DaemonApi
    , daemonApi

    , swagger

    , MachineId(..)
    ) where

import           Protolude

import           Data.Aeson ((.:), (.=))
import qualified Data.Aeson as A
import           Data.Swagger
import           Data.Version (showVersion)
import qualified Network.HTTP.Media as HttpMedia
import           Radicle.Daemon.Ipfs
import           Servant.API
import           Servant.Swagger

import qualified Paths_radicle as Radicle
import qualified Radicle.Internal.Annotation as Ann
import           Radicle.Internal.Core
import           Radicle.Internal.Parse
import           Radicle.Internal.Pretty

data RadicleData

instance Accept RadicleData where
  contentType _ = "application" HttpMedia.// "radicle"

instance ToRad Ann.WithPos a => MimeRender RadicleData a where
  mimeRender _ = toS . renderCompactPretty . (toRad :: a -> Value)

instance FromRad Ann.WithPos a => MimeUnrender RadicleData a where
  mimeUnrender _ = first toS . (fromRad <=< parse "[daemon]") . toS

instance FromHttpApiData MachineId where
    parseUrlPiece = Right . MachineId . toS
    parseQueryParam = parseUrlPiece

instance ToHttpApiData MachineId where
    toUrlPiece (MachineId id) = id

newtype QueryRequest = QueryRequest { expression :: Value }
  deriving (Generic)

instance FromRad Ann.WithPos QueryRequest
instance ToRad Ann.WithPos QueryRequest

instance A.ToJSON QueryRequest where
    toJSON QueryRequest{..} = A.object
        [ "expression" .= valueToJson expression
        ]
instance A.FromJSON QueryRequest where
    parseJSON = A.withObject "QueryRequest" $ \o -> do
        expression <- o .: "expression" >>= jsonToValue
        pure $ QueryRequest {..}

newtype QueryResponse = QueryResponse { result :: Value }
  deriving (Generic)

instance FromRad Ann.WithPos QueryResponse
instance ToRad Ann.WithPos QueryResponse

instance A.ToJSON QueryResponse where
    toJSON QueryResponse{..} = A.object
        [ "result" .= valueToJson result
        ]
instance A.FromJSON QueryResponse where
    parseJSON = A.withObject "QueryResponse" $ \o -> do
        result <- o .: "result" >>= jsonToValue
        pure $ QueryResponse {..}

newtype SendRequest = SendRequest { expressions :: [Value] }
  deriving (Generic)

instance FromRad Ann.WithPos SendRequest
instance ToRad Ann.WithPos SendRequest

instance A.FromJSON SendRequest where
    parseJSON = A.withObject "SendRequest" $ \o -> do
        expressions <- o .: "expressions" >>= traverse jsonToValue
        pure $ SendRequest {..}
instance A.ToJSON SendRequest where
    toJSON SendRequest{..} = A.object
        [ "expressions" .= map valueToJson expressions
        ]

newtype SendResponse = SendResponse
  { results :: [Value]
  } deriving (Generic)

instance FromRad Ann.WithPos SendResponse
instance ToRad Ann.WithPos SendResponse

instance A.FromJSON SendResponse where
    parseJSON = A.withObject "SendResponse" $ \o -> do
        results <- o .: "results" >>= traverse jsonToValue
        pure $ SendResponse {..}
instance A.ToJSON SendResponse where
    toJSON SendResponse{..} = A.object
        [ "results" .= map valueToJson results
        ]

newtype NewResponse = NewResponse
  { machineId :: MachineId
  } deriving (Generic)

instance ToRad Ann.WithPos MachineId
instance FromRad Ann.WithPos MachineId

instance ToRad Ann.WithPos NewResponse
instance FromRad Ann.WithPos NewResponse

instance A.ToJSON NewResponse
instance A.FromJSON NewResponse

-- * APIs

type Formats = '[JSON, RadicleData]

type MachinesEndpoint t = "v0" :> "machines" :> t
type MachineEndpoint t = MachinesEndpoint (Capture "machineId" MachineId :> t)

type MachineQueryEndpoint = MachineEndpoint ("query" :> ReqBody Formats QueryRequest :> Post Formats QueryResponse)
machineQueryEndpoint :: Proxy MachineQueryEndpoint
machineQueryEndpoint = Proxy

type MachineSendEndpoint = MachineEndpoint ("send" :> ReqBody Formats SendRequest :> Post Formats SendResponse)
machineSendEndpoint :: Proxy MachineSendEndpoint
machineSendEndpoint = Proxy

type NewMachineEndpoint = MachinesEndpoint ("new" :> Post Formats NewResponse)
newMachineEndpoint :: Proxy NewMachineEndpoint
newMachineEndpoint = Proxy

type DaemonApi =
         NewMachineEndpoint
    :<|> MachineQueryEndpoint
    :<|> MachineSendEndpoint
    :<|> "v0" :> "docs" :> Get '[JSON] Swagger

daemonApi :: Proxy DaemonApi
daemonApi = Proxy

-- * Docs

instance ToParamSchema MachineId where
  toParamSchema _ = mempty { _paramSchemaType = SwaggerString }
instance ToSchema MachineId where
  declareNamedSchema pxy = pure $
    NamedSchema (Just "MachineId") $
      mempty { _schemaDescription = Just "The ID (i.e. IPNS name) of an IPFS machine."
             , _schemaParamSchema = toParamSchema pxy }

instance ToSchema Value where
  declareNamedSchema _ = pure $
    NamedSchema (Just "RadicleValue") $
      mempty { _schemaDescription = Just "A radicle value formatted according to radicle's S-expression syntax."
             , _schemaParamSchema = mempty {_paramSchemaType = SwaggerString } }

instance ToSchema QueryRequest
instance ToSchema QueryResponse
instance ToSchema SendRequest
instance ToSchema SendResponse
instance ToSchema NewResponse

instance ToSchema Swagger where
  declareNamedSchema _ = pure $
    NamedSchema (Just "Swagger") $
      mempty { _schemaDescription = Just "This swagger spec."
             , _schemaParamSchema = mempty { _paramSchemaType = SwaggerObject }}

swagger :: Swagger
swagger = swag { _swaggerInfo = inf }
  where
    inf = mempty { _infoTitle = "Radicle daemon"
                 , _infoDescription = Just desc
                 , _infoVersion = toS $ showVersion Radicle.version
                 }
    swag = toSwagger daemonApi
    desc =
      "The radicle-daemon; a long-running background process which\
      \ materialises the state of remote IPFS machines on the users\
      \ PC, and writes to those IPFS machines the user is an owner of."
