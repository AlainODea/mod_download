%% @author Alain O'Dea <alain.odea@gmail.com>
%% @copyright 2011 Alain O'Dea
%% @date 2011-01-21
%% @doc Download Link Module.  Provides ACL-free access to protected resources.  This is intended to be used in conjunction with a secure URL generation mechanism such as the one used by mod_paypal.

%% Copyright 2011 Alain O'Dea
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%% 
%%     http://www.apache.org/licenses/LICENSE-2.0
%% 
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.

-module(mod_download).
-author("Alain O'Dea <alain.odea@gmail.com>").

-mod_title("Hidden Downloads").
-mod_description("Allow download resources to exist that are hidden from feeds.").
