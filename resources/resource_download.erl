%% @author Alain O'Dea <alain.odea@gmail.com>
%% @copyright 2011 Lloyd R. Prentice
%%
%% @doc Serve static (image) files from a configured list of directories or template lookup keys.  Caches files in the local depcache.
%% Is also able to generate previews (if configured to do so).

%% Copyright 2011 Lloyd R. Prentice
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

-module(resource_download).
-export([
    init/1,
    service_available/2,
    allowed_methods/2,
    resource_exists/2,
    last_modified/2,
    expires/2,
    content_types_provided/2,
    charsets_provided/2,
    encodings_provided/2,
    provide_content/2,
    finish_request/2
]).

-include_lib("webmachine_resource.hrl").
-include_lib("zotonic.hrl").

-record(cache, {path, fullpath, mime, last_modified, body}).

-define(MAX_AGE, 315360000).
-define(CHUNKED_CONTENT_LENGTH, 1048576).
-define(CHUNK_LENGTH, 65536).

-define(DELEGATE, resource_file_readonly).

init(ConfigProps) ->
    ?DELEGATE:init(ConfigProps).

allowed_methods(ReqData, Context) ->
    ?DELEGATE:allowed_methods(ReqData, Context).

content_types_provided(ReqData, Context) ->
    ?DELEGATE:content_types_provided(ReqData, Context).

encodings_provided(ReqData, Context) ->
    ?DELEGATE:encodings_provided(ReqData, Context).

resource_exists(ReqData, Context) ->
    ?DELEGATE:resource_exists(ReqData, Context).

charsets_provided(ReqData, Context) ->
    ?DELEGATE:charsets_provided(ReqData, Context).

last_modified(ReqData, Context) ->
    ?DELEGATE:last_modified(ReqData, Context).

expires(ReqData, Context) ->
    ?DELEGATE:expires(ReqData, Context).

provide_content(ReqData, Context) ->
    ?DELEGATE:provide_content(ReqData, Context).

%% The rest of this is shameless copy-pasting of code from the delegate
%% module `resource_file_readonly` to work around reuse constraints.
%%
%% The only material difference is in `ensure_file_info/2` where
%% the ID of the attached media is substituted into the Context using
%% `get_download_rsc/2` instead of
%% `m_rsc:rid(z_context:get_q("id", Context), Context)`
get_download_rsc(ReqData, Context) ->
    {ok, DownloadId} = m_rsc:page_path_to_id(m_req:get(raw_path, ReqData), Context),
    % redirect further processing to the embedded media resource
    [RscId] = m_rsc:media(DownloadId, Context),
    RscId.

%% @doc Redirect to the underlying media to be downloaded
service_available(ReqData, ConfigProps) ->
    Context = z_context:set(ConfigProps, z_context:new(ReqData)),
    Context1 = z_context:ensure_qs(z_context:continue_session(Context)),
    
    try ensure_file_info(ReqData, Context1) of
        {_, ContextFile} ->
            % Use chunks for large files
            case z_context:get(fullpath, ContextFile) of
                undefined -> 
                    ?WM_REPLY(true, ContextFile);
                FullPath ->
                    case catch filelib:file_size(FullPath) of
                        N when is_integer(N) ->
                            case N > ?CHUNKED_CONTENT_LENGTH of
                                true -> 
                                    ContextChunked = z_context:set([{chunked, true}, {file_size, N}], ContextFile), 
                                    ?WM_REPLY(true, ContextChunked);
                                false ->
                                    ContextSize = z_context:set([{file_size, N}], ContextFile), 
                                    ?WM_REPLY(true, ContextSize)
                            end;
                        _ ->
                            ?WM_REPLY(true, ContextFile)
                    end
            end
    catch 
        _:checksum_invalid ->
            %% Not a nice solution, but since 'resource_exists'
            %% are checked much later in the wm flow, we would otherwise 
            %% have to break the logical flow, and introduce some ugly
            %% condition checking in the intermediate callback functions.            
            ?WM_REPLY(false, Context1)
    end.

finish_request(ReqData, Context) ->
    case z_context:get(is_cached, Context) of
        false ->
            case z_context:get(body, Context) of
                undefined ->  
                    {ok, ReqData, Context};
                Body ->
                    case z_context:get(use_cache, Context, false) andalso z_context:get(encode_data, Context, false) of
                        true ->
                            % Cache the served file in the depcache.  Cache it for 3600 secs.
                            Path = z_context:get(path, Context),
                            Cache = #cache{
                                path=Path,
                                fullpath=z_context:get(fullpath, Context),
                                mime=z_context:get(mime, Context),
                                last_modified=z_context:get(last_modified, Context),
                                body=Body
                            },
                            z_depcache:set(cache_key(Path), Cache, Context),
                            {ok, ReqData, Context};
                        _ ->
                            % No cache or no gzip'ed version (file system cache is fast enough for image serving)
                            {ok, ReqData, Context}
                    end
            end;
        true ->
            {ok, ReqData, Context}
    end.


%%%%%%%%%%%%%% Helper functions %%%%%%%%%%%%%%

%% @doc Find the file referred to by the reqdata or the preconfigured path
ensure_file_info(ReqData, Context) ->
    {Path, ContextPath} = case z_context:get(path, Context) of
                             undefined ->
                                 FilePath = mochiweb_util:safe_relative_path(mochiweb_util:unquote(wrq:disp_path(ReqData))),
                                 rsc_media_check(FilePath, Context);
                             id ->
                                 RscId = get_download_rsc(ReqData, Context),
                                 ContextRsc = z_context:set(id, RscId, Context),
                                 case m_media:get(RscId, ContextRsc) of
                                     undefined ->
                                         {undefined, ContextRsc};
                                     Media ->
                                         {z_convert:to_list(proplists:get_value(filename, Media)),
                                          z_context:set(mime, z_convert:to_list(proplists:get_value(mime, Media)), ContextRsc)}
                                 end;
                             ConfiguredPath ->
                                 {ConfiguredPath, Context}
                         end,

    Cached = case z_context:get(use_cache, ContextPath) of
                 true -> z_depcache:get(cache_key(Path), ContextPath);
                 _    -> undefined
             end,
    case Cached of
        undefined ->
            ContextMime = case z_context:get(mime, ContextPath) of
                              undefined -> z_context:set(mime, z_media_identify:guess_mime(Path), ContextPath);
                              _Mime -> ContextPath
                          end,
            case file_exists(Path, ContextMime) of 
                {true, FullPath} ->
                    {true, z_context:set([ {path, Path}, {fullpath, FullPath} ], ContextMime)};
                _ -> 
                    %% We might be able to generate a new preview
                    case z_context:get(is_media_preview, ContextMime, false) of
                        true ->
                            % Generate a preview, recurse on success
                            ensure_preview(Path, ContextMime);
                        false ->
                            {false, ContextMime}
                    end
            end;
        {ok, Cache} ->
            {true, z_context:set([ {is_cached, true},
                                            {path, Cache#cache.path},
                                            {fullpath, Cache#cache.fullpath},
                                            {mime, Cache#cache.mime},
                                            {last_modified, Cache#cache.last_modified},
                                            {body, Cache#cache.body}
                                          ],
                                          ContextPath)}
    end.


rsc_media_check(undefined, Context) ->
    {undefined, Context};
rsc_media_check(File, Context) ->
    {BaseFile, IsResized, Context1} = case lists:member($(, File) of
                            true ->
                                {File1, Proplists, Check, Prop} = z_media_tag:url2props(File, Context),
                                {File1, true, z_context:set(media_tag_url2props, {File1, Proplists, Check, Prop}, Context)};
                            false ->
                                {File, false, Context}
                          end,
    case m_media:get_by_filename(BaseFile, Context1) of
        undefined ->
            {File, Context1};
        Media ->
            MimeOriginal = z_convert:to_list(proplists:get_value(mime, Media)),
            Props = [
                {id, proplists:get_value(id, Media)},
                {mime_original, MimeOriginal}
            ],
            Props1 = case IsResized of 
                        true -> [ {mime, z_media_identify:guess_mime(File)} | Props ];
                        false -> [ {mime, MimeOriginal} | Props ]
                     end,
            {File, z_context:set(Props1, Context1)}
    end.



cache_key(Path) ->
    {resource_file, Path}.

file_exists(undefined, _Context) ->
    false;
file_exists([], _Context) ->
    false;
file_exists(Name, Context) ->
    RelName = case hd(Name) of
                  $/ -> tl(Name);
                  _ -> Name
              end,
    case mochiweb_util:safe_relative_path(RelName) of
        undefined -> false;
        SafePath ->
            RelName = case hd(SafePath) of
                          "/" -> tl(SafePath);
                          _ -> SafePath
                      end,
            Root = case z_context:get(root, Context) of
                       undefined -> 
                           case z_context:get(is_media_preview, Context, false) of
                               true  -> [z_path:media_preview(Context)];
                               false -> [z_path:media_archive(Context)]
                           end;
                       ConfRoot -> ConfRoot
                   end,
            file_exists1(Root, RelName, Context)
    end.

file_exists1([], _RelName, _Context) ->
    false;
file_exists1([ModuleIndex|T], RelName, Context) when is_atom(ModuleIndex) ->
    case z_module_indexer:find(ModuleIndex, RelName, Context) of
        {ok, File} -> {true, File};
        {error, _} -> file_exists1(T, RelName, Context)
    end;
file_exists1([{module, Module}|T], RelName, Context) ->
    case Module:file_exists(RelName, Context) of
        false -> file_exists1(T, RelName, Context);
        Result -> Result
    end;
file_exists1([DirName|T], RelName, Context) ->
    NamePath = filename:join([DirName,RelName]),
    case filelib:is_regular(NamePath) of 
    true ->
        {true, NamePath};
    false ->
        file_exists1(T, RelName, Context)
    end.

%% @spec ensure_preview(ReqData, Path, Context) -> {Boolean, NewContext}
%% @doc Generate the file on the path from an archived media file.
%% The path is like: 2007/03/31/wedding.jpg(300x300)(crop-center)(709a-a3ab6605e5c8ce801ac77eb76289ac12).jpg
%% The original media should be in State#media_path (or z_path:media_archive)
%% The generated image should be created in State#root (or z_path:media_preview)
ensure_preview(Path, Context) ->
    {Filepath, PreviewPropList, _Checksum, _ChecksumBaseString} = 
                    case z_context:get(media_tag_url2props,Context) of
                        undefined -> z_media_tag:url2props(Path, Context);
                        MediaInfo -> MediaInfo
                    end,
    case mochiweb_util:safe_relative_path(Filepath) of
        undefined ->
            {false, Context};
        Safepath  ->
            MediaPath = case z_context:get(media_path, Context) of
                            undefined -> z_path:media_archive(Context);
                            ConfMediaPath -> ConfMediaPath
                        end,
            
            MediaFile = case Safepath of 
                            "lib/" ++ LibPath ->  
                                case z_module_indexer:find(lib, LibPath, Context) of 
                                    {ok, ModuleFilename} -> ModuleFilename; 
                                    {error, _} -> filename:join(MediaPath, Safepath) 
                                end; 
                            _ -> 
                                filename:join(MediaPath, Safepath) 
                        end,
            case filelib:is_regular(MediaFile) of
                true ->
                    % Media file exists, perform the resize
                    Root = case z_context:get(root, Context) of
                               [ConfRoot|_] -> ConfRoot;
                               _ -> z_path:media_preview(Context)
                           end,
                    PreviewFile = filename:join(Root, Path),
                    case z_media_preview:convert(MediaFile, PreviewFile, PreviewPropList, Context) of
                        ok -> {true, z_context:set(fullpath, PreviewFile, Context)};
                        {error, Reason} -> throw(Reason)
                    end;
                false ->
                    {false, Context}
            end
    end.
