Zotonic Hidden Download Module
==============================
This module is heavily based on `resource_file_readonly` from `mod_base`.  It makes it possible to provide download links for media that is unpublished.  The notion behind this odd use case is that every published item is aggregated into the Atom feed and we really don't want things like download links for purchases to be in a feed.

This is designed primarily to support `mod_paypal`.