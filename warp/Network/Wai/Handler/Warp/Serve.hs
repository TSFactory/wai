module Network.Wai.Handler.Warp.Serve
  ( WarpServant
  , allocateWarpServant
  , serveConnection
  ) where

import Control.Exception (bracket)
import Control.Monad.IO.Class
import Control.Monad.Trans.Resource
import Network.Socket (SockAddr)
import Network.Wai
import Network.Wai.Handler.Warp.Settings
import Network.Wai.Handler.Warp.Types
import qualified Network.Wai.Handler.Warp.Date as D
import qualified Network.Wai.Handler.Warp.FdCache as F
import qualified Network.Wai.Handler.Warp.FileInfoCache as I
import qualified Network.Wai.Handler.Warp.Run as R
import qualified Network.Wai.Handler.Warp.Timeout as T

-- | WarpServant encapsulates web server state shared across connections. Using it
-- allows you to take over an existing single connection as if it was established by
-- Warp itself ('serveConnection')
data WarpServant = WarpServant
  { warpInternalInfo :: InternalInfo
  , warpSettings     :: Settings
  }

allocateWarpServant :: Settings -> ResourceT IO (ReleaseKey, WarpServant)
allocateWarpServant set = do
  (tmRelease, tm) <- case settingsManager set of
    Just tm -> register (return ()) >>= \ra -> return (ra, tm)
    Nothing -> allocate (T.initialize $ settingsTimeout set * 1000000) T.stopManager
  dateCache <- liftIO D.initialize
  (fcRelease, fileCache) <- allocate (F.initialize $ settingsFdCacheDuration set * 1000000) F.terminate
  (ficRelease, fileInfoCache) <- allocate (I.initialize $ settingsFileInfoCacheDuration set * 1000000) I.terminate

  releaseAll <- register (release ficRelease >> release fcRelease >> release tmRelease)
  let ii0 = InternalInfo undefined tm fileCache (I.getAndRegisterInfo fileInfoCache) (I.getAndRegisterInfo' fileInfoCache) dateCache
  return (releaseAll, WarpServant ii0 set)

serveConnection :: WarpServant -> (Connection, SockAddr) -> Application -> IO ()
serveConnection (WarpServant ii set) (c, sa) app =
  bracket (T.registerKillThread (timeoutManager ii)) T.cancel $ \th ->
    R.serveConnection c ii { threadHandle = th } sa TCP set app
