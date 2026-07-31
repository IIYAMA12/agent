---@meta
--- Editor-only LuaLS types for the agent resource.
--- Not loaded by MTA (do not add to meta.xml).
--- Optional: add mtasa-blue Lua defs to workspace.library in .luarc.json for full MTA API stubs.

--------------------------------------------------------------------------------
-- MTA element aliases
--------------------------------------------------------------------------------

---@alias element userdata
---@alias player element
---@alias ped element
---@alias vehicle element
---@alias object element
---@alias pickup element
---@alias marker element
---@alias colshape element
---@alias blip element
---@alias radararea element
---@alias team element
---@alias resource userdata
---@alias acl userdata
---@alias aclgroup userdata
---@alias account userdata
---@alias timer userdata
---@alias xmlnode userdata
---@alias file userdata

--- Minimal MTA API stubs used by this resource (not a full wiki dump).
---@type fun(category?: string, options?: string, filter?: string): string[]|nil, table[]|nil
getPerformanceStats = nil

---@type fun(): table|nil
getProcessMemoryStats = nil

---@type fun(): any
getFPSLimit = nil

---@type fun(): table|nil
getNetworkUsageData = nil

---@type fun(player?: player): table|nil
getNetworkStats = nil

---@type fun(): boolean
isTransferBoxActive = nil

---@type fun(): table|nil
dxGetStatus = nil

---@type fun(theResource: resource): boolean
startResource = nil

---@type fun(theResource: resource): boolean
stopResource = nil

---@type fun(theResource: resource): boolean
restartResource = nil

--------------------------------------------------------------------------------
-- Agent namespace (constants + attached namespaces)
--------------------------------------------------------------------------------

---@class Agent
---@field PERSIST_MEMORY boolean
---@field RESOURCE_NAME string
---@field SERIAL_LENGTH integer
---@field ELEMENT_SIDE_SERVER "server"
---@field ELEMENT_SIDE_CLIENT "client"
---@field NEARBY_DEFAULT_TYPES string[]
---@field WALKER_HANDLE_TYPES string[]
---@field WALKER_DEFAULT_MAX_DEPTH integer
---@field WALKER_DEFAULT_MAX_NODES integer
---@field WALKER_LARGE_MAP_THRESHOLD integer
---@field WALKER_DEFAULT_MAP_CHILD_LIMIT integer
---@field WALKER_DEFAULT_AUTO_TRACK_CHILD_LIMIT integer
---@field GUI_ELEMENT_TYPES string[]
---@field GUI_WALKER_DEFAULT_MAX_DEPTH integer
---@field GUI_WALKER_DEFAULT_MAX_NODES integer
---@field GUI_SCAN_TIMEOUT_MS integer
---@field VISIBLE_QUERY_TIMEOUT_MS integer
---@field EVENT_HOOK_TIMEOUT_MS integer
---@field DEBUG_LOG_FETCH_TIMEOUT_MS integer
---@field HEALTH_FETCH_TIMEOUT_MS integer
---@field CLIENT_EVAL_TIMEOUT_MS integer
---@field CLIENT_RESPONSE_TIMEOUT_MS integer
---@field CLIENT_REQUEST_TIMEOUT_MS integer
---@field CLIENT_EVENT_REQUEST string
---@field CLIENT_EVENT_RESPONSE string
---@field CLIENT_EVENT_READY string
---@field AREAS AgentArea[]
---@field AIRPORTS AgentArea[]
---@field registry AgentRegistryState|nil
---@field DebugLog AgentDebugLogNS
---@field EventHook AgentEventHookNS
---@field Health AgentHealthNS
--- Async / bridge runtime state (server + client)
---@field clientCallbacks table<string, fun(ok: boolean, result: any)>
---@field loadedClients table<player, boolean>
---@field clientNextId integer
---@field clientRequests table<string, AgentAsyncRequest>
---@field clientRequestNextId integer
---@field clientEvalRequests table<string, AgentClientEvalRequest>
---@field clientEvalNextId integer
---@field visibleRequests table<string, AgentAsyncRequest>
---@field visibleNextId integer
---@field lookTargetRequests table<string, AgentAsyncRequest>
---@field lookTargetNextId integer
---@field guiScanRequests table<string, AgentAsyncRequest>
---@field guiScanNextId integer
---@field debugLogRequests table<string, AgentAsyncRequest>
---@field debugLogNextId integer
---@field serverDebugBuffer table
---@field clientDebugBuffer table
---@field eventHookRequests table<string, AgentAsyncRequest>
---@field eventHookNextId integer
---@field serverEventTracker AgentEventTracker
---@field clientEventTracker AgentEventTracker
---@field healthRequests table<string, AgentAsyncRequest>
---@field healthNextId integer
---@field memoryStore table<string, any>
---@field dbConnection userdata|nil
---@field dbReady boolean
---@field clientShadows table<string, AgentClientShadowStore>

---@class AgentClientShadowStore
---@field byId table<string, AgentRegistryEntry>

---@class AgentRegistryState
---@field startupAt integer
---@field side string
---@field seq integer
---@field byId table<string, AgentRegistryEntry>
---@field byElement table<element, AgentRegistryEntry>

---@class AgentParsedElementId
---@field side "server"|"client"
---@field startupAt integer
---@field seq integer

---@class AgentDebugLogNS
---@field MAX_SIZE integer
---@field LEVEL_NAMES table<integer, string>
---@field normalizeEntry fun(message: string|any, level?: integer, file?: string, line?: integer, r?: integer, g?: integer, b?: integer, side?: string, player?: string): AgentDebugLogEntry
---@field entryFingerprint fun(entry: AgentDebugLogEntry|table): string
---@field filterEntries fun(entries: AgentDebugLogEntry[], options?: AgentDebugLogOptions|table): AgentDebugLogEntry[]
---@field mergeEntries fun(listA: AgentDebugLogEntry[], listB: AgentDebugLogEntry[], options?: AgentDebugLogOptions|table): AgentDebugLogEntry[]
---@field createBuffer fun(maxSize?: integer): table
---@field makeCaptureHandler fun(buffer: table, side?: string, enrichFn?: fun(entry: AgentDebugLogEntry)): fun(message: string, level?: integer, file?: string, line?: integer, r?: integer, g?: integer, b?: integer)

---@class AgentEventHookNS
---@field MAX_SIZE integer
---@field VALID_HOOK_TYPES table<string, boolean>
---@field DEFAULT_HOOK_TYPES string[]
---@field argPreview fun(args?: any[], maxArgs?: integer): string
---@field normalizeHookTypes fun(hookTypes?: string[]): string[]
---@field normalizeNameList fun(options: AgentEventHookControlOptions|AgentEventHookListOptions|table): string[]|nil
---@field buildEntry fun(hookType: string, side: string, player?: string, fields?: table): AgentEventHookEntry
---@field entryFingerprint fun(entry: AgentEventHookEntry|table): string
---@field filterEntries fun(entries: AgentEventHookEntry[], options?: AgentEventHookListOptions|table): AgentEventHookEntry[]
---@field mergeEntries fun(listA: AgentEventHookEntry[], listB: AgentEventHookEntry[], options?: AgentEventHookListOptions|table): AgentEventHookEntry[]
---@field createTracker fun(side: string, playerGetter?: fun(): string|nil): AgentEventTracker

---@class AgentEventTracker
---@field side string
---@field buffer table
---@field active boolean
---@field callbacks table
---@field hookTypes string[]
---@field nameList string[]|nil
---@field startedAt integer|nil
---@field playerGetter fun(): string|nil|nil
---@field makeCallback fun(self: AgentEventTracker, hookType: string): function
---@field start fun(self: AgentEventTracker, options?: AgentEventHookControlOptions|table): AgentEventHookStatus
---@field stop fun(self: AgentEventTracker): AgentEventHookStatus
---@field clear fun(self: AgentEventTracker): AgentEventHookStatus
---@field status fun(self: AgentEventTracker): AgentEventHookStatus
---@field snapshot fun(self: AgentEventTracker, options?: AgentEventHookListOptions|table): AgentEventHookSnapshot

---@class AgentHealthNS
---@field normalizeMemory fun(stats?: table): table|nil
---@field formatPerformanceTable fun(columns: string[], rows: table[]): { columns: string[], rows: table[], rowCount: integer }
---@field listPerformanceCategories fun(): { columns: string[], rows: table[], rowCount: integer }|nil
---@field collectPerformance fun(category: string, perfOptions?: string, filter?: string): { columns: string[], rows: table[], rowCount: integer }|nil
---@field summarizeNetworkUsage fun(data?: table, limit?: integer): table|nil
---@field safeCall fun(fn?: function, ...: any): any|nil
---@field parsePercentValue fun(text?: string|number): number|nil
---@field parseCpuValue fun(text?: string): table|nil
---@field parseFpsSyncValue fun(text?: string): table|nil
---@field collectThreadCpu fun(): table|nil
---@field collectLuaTimingCpu fun(limit?: integer): table|nil
---@field collectCpu fun(options?: AgentHealthOptions|table, context?: table): table|nil
---@field collectSnapshot fun(options?: AgentHealthOptions|table, context?: table): AgentHealthSnapshot

--------------------------------------------------------------------------------
-- Shared primitives
--------------------------------------------------------------------------------

---@class AgentVec3
---@field x number
---@field y number
---@field z number

---@class AgentColor
---@field r number
---@field g number
---@field b number

---@class AgentPlayerInfo
---@field name string
---@field serial string

---@class AgentResolvePlayerOptions
---@field serial? string

---@class AgentOccupiedVehicleRef
---@field id string
---@field model integer

---@class AgentJsonResponse
---@field status integer
---@field headers table<string, string>
---@field body string

---@class AgentHttpRequest
---@field method string
---@field path string
---@field query? table<string, string>
---@field body? string

---@class AgentHttpPayload
---@field ok boolean
---@field error? string
---@field result? any

--------------------------------------------------------------------------------
-- Registry
--------------------------------------------------------------------------------

---@class AgentRegistryEntry
---@field id string
---@field side "server"|"client"
---@field localOnly boolean
---@field owner? string
---@field elementType string
---@field mtaHandle string
---@field startupAt integer
---@field createdAt integer
---@field lastSeenAt integer
---@field label? string
---@field meta table
---@field props table
---@field source string
---@field alive boolean
---@field element? element

---@class AgentElementFilters
---@field alive? boolean
---@field side? "server"|"client"
---@field localOnly? boolean
---@field owner? string
---@field elementType? string
---@field label? string
---@field source? string
---@field includeClientShadows? boolean

---@class AgentTrackElementOpts
---@field label? string
---@field meta? table
---@field source? string
---@field owner? string
---@field elementType? string
---@field parentElement? element
---@field parent? element
---@field parentMtaHandle? string
---@field parentElementType? string
---@field maxDepth? integer
---@field parentMaxDepth? integer
---@field refresh? boolean
---@field mtaHandle? string
---@field id? string
---@field side? "server"|"client"
---@field sync? boolean
---@field syncClient? boolean
---@field player? string
---@field serial? string
---@field type? string
---@field types? string[]
---@field limit? integer
---@field maxDistance? number
---@field model? integer|string
---@field search? string

---@class AgentAutoTrackOpts
---@field autoTrack? boolean
---@field track? boolean
---@field trackSource? string
---@field source? string
---@field trackLabel? string
---@field trackMeta? table

---@class AgentGetElementOptions
---@field refresh? boolean
---@field player? string
---@field serial? string
---@field sync? boolean
---@field side? "server"|"client"

---@class AgentElementModifySet
---@field position? AgentVec3
---@field rotation? AgentVec3
---@field dimension? integer
---@field interior? integer
---@field health? number
---@field frozen? boolean
---@field alpha? integer
---@field locked? boolean
---@field engine? boolean
---@field plate? string
---@field armor? number
---@field skin? integer

---@class AgentElementModifyOps
---@field set? AgentElementModifySet

--------------------------------------------------------------------------------
-- Nearby / discovery props
--------------------------------------------------------------------------------

---@class AgentNearbyBaseProps
---@field elementType string
---@field id string
---@field distance? number
---@field position AgentVec3
---@field dimension integer
---@field interior integer
---@field agentId? string

---@class AgentNearbyVehicleProps : AgentNearbyBaseProps
---@field model integer
---@field name? string
---@field health number
---@field locked boolean
---@field engine boolean
---@field plate string
---@field rotation AgentVec3
---@field occupants integer

---@class AgentNearbyPlayerProps : AgentNearbyBaseProps
---@field name string
---@field health number
---@field armor number
---@field ping integer
---@field team? string
---@field weapon integer
---@field inVehicle boolean
---@field vehicle? AgentOccupiedVehicleRef

---@class AgentNearbyPedProps : AgentNearbyBaseProps
---@field model integer
---@field health number
---@field inVehicle boolean

---@class AgentNearbyObjectProps : AgentNearbyBaseProps
---@field model integer
---@field rotation AgentVec3

---@class AgentNearbyPickupProps : AgentNearbyBaseProps
---@field pickupType integer
---@field amount number
---@field weapon? integer

---@class AgentNearbyMarkerProps : AgentNearbyBaseProps
---@field markerType string
---@field size number

---@alias AgentNearbyProps AgentNearbyBaseProps|AgentNearbyVehicleProps|AgentNearbyPlayerProps|AgentNearbyPedProps|AgentNearbyObjectProps|AgentNearbyPickupProps|AgentNearbyMarkerProps

---@class AgentNearbyOptions : AgentResolvePlayerOptions, AgentAutoTrackOpts
---@field type? string
---@field types? string[]
---@field limit? integer
---@field maxDistance? number
---@field perType? boolean
---@field perTypeLimit? integer
---@field excludeSelf? boolean

---@class AgentNearbyResult
---@field player string
---@field origin AgentVec3
---@field results AgentNearbyProps[]

--------------------------------------------------------------------------------
-- Visible / look target
--------------------------------------------------------------------------------

---@class AgentScreenDebug
---@field onScreen boolean
---@field normalized? { x: number, y: number }
---@field pixels? { x: integer, y: integer }
---@field centerDistance? number

---@class AgentElementDebug
---@field visible boolean
---@field onScreen boolean
---@field streamedIn boolean
---@field alpha integer
---@field screen AgentScreenDebug
---@field dimension integer
---@field interior integer
---@field lineOfSight? boolean
---@field collisionsEnabled? boolean
---@field cameraAngle? number
---@field lookMethod? "raycast"|"screenCenter"
---@field hitPosition? AgentVec3

---@class AgentVisibleElementProps : AgentNearbyBaseProps
---@field debug AgentElementDebug

---@class AgentCameraState
---@field position AgentVec3
---@field lookAt AgentVec3
---@field forward? AgentVec3
---@field viewport { width: integer, height: integer }

---@class AgentVisibleStats
---@field scanned integer
---@field streamedIn integer
---@field onScreen integer
---@field visible integer
---@field returned integer

---@class AgentVisibleOptions : AgentResolvePlayerOptions, AgentAutoTrackOpts
---@field type? string
---@field types? string[]
---@field limit? integer
---@field maxDistance? number
---@field lineOfSight? boolean
---@field includeOffScreen? boolean
---@field onlyVisible? boolean
---@field debugLog? boolean

---@class AgentLookOptions : AgentResolvePlayerOptions, AgentAutoTrackOpts
---@field type? string
---@field types? string[]
---@field maxDistance? number
---@field lineOfSight? boolean
---@field debugLog? boolean
---@field screenCenterMax? number
---@field maxCameraAngle? number

---@class AgentLookResult
---@field player string
---@field origin AgentVec3
---@field camera AgentCameraState
---@field method? "raycast"|"screenCenter"|nil
---@field lookingAt? AgentVisibleElementProps|table|nil

---@class AgentVisibleResult : AgentLookResult
---@field stats AgentVisibleStats
---@field elements AgentVisibleElementProps[]

--------------------------------------------------------------------------------
-- Areas / teleport
--------------------------------------------------------------------------------

---@class AgentArea
---@field id string
---@field name string
---@field category string
---@field region string
---@field x number
---@field y number
---@field z number
---@field rotation number

---@class AgentAreaFilters
---@field locationId? string
---@field airportId? string
---@field areaId? string
---@field id? string
---@field category? string
---@field type? string
---@field region? string
---@field search? string
---@field name? string

---@class AgentAreaMap
---@field total integer
---@field categories table<string, integer>
---@field regions table<string, integer>
---@field areas AgentArea[]

---@class AgentTeleportAreaOptions : AgentAreaFilters, AgentResolvePlayerOptions
---@field includeVehicle? boolean
---@field rotation? number
---@field interior? integer
---@field dimension? integer

---@class AgentTeleportElementOptions : AgentResolvePlayerOptions
---@field targetPlayer? string
---@field toPlayer? string
---@field target? string
---@field playerTarget? string
---@field allowSelf? boolean
---@field elementId? string
---@field type? string
---@field elementType? string
---@field types? string[]
---@field model? integer|string
---@field name? string
---@field search? string
---@field maxDistance? number
---@field offset? AgentVec3
---@field offsetDistance? number
---@field offsetZ? number
---@field rotation? number
---@field matchWorld? boolean
---@field includeVehicle? boolean
---@field interior? integer
---@field dimension? integer

---@class AgentTeleportPositionOptions : AgentResolvePlayerOptions
---@field includeVehicle? boolean
---@field rotation? number
---@field interior? integer
---@field dimension? integer

--------------------------------------------------------------------------------
-- Element walker
--------------------------------------------------------------------------------

---@class AgentWalkOptions : AgentAutoTrackOpts, AgentResolvePlayerOptions
---@field mode? "resourceTops"|"roots"|string
---@field rootsOnly? boolean
---@field resourceName? string
---@field rootId? string
---@field root? element
---@field childType? string
---@field elementType? string
---@field maxDepth? integer
---@field maxNodes? integer
---@field flat? boolean
---@field resourceState? boolean
---@field resourcesOnly? boolean
---@field side? "server"|"client"
---@field player? string
---@field query? string
---@field q? string
---@field state? string
---@field limit? integer
---@field runningOnly? boolean
---@field listMapChildren? boolean
---@field mapChildLimit? integer
---@field autoTrackChildren? boolean
---@field autoTrackChildLimit? integer
---@field parentMtaHandle? string
---@field parentElementType? string

---@class AgentWalkerNode
---@field elementType string
---@field mtaHandle string
---@field elementId? string
---@field depth integer
---@field path string
---@field resourceName? string
---@field resourceState? string
---@field localOnly? boolean
---@field agentId? string
---@field childCount? integer
---@field depthLimit? boolean
---@field children? AgentWalkerNode[]
---@field truncated? boolean
---@field reason? string

--------------------------------------------------------------------------------
-- GUI scan
--------------------------------------------------------------------------------

---@class AgentGuiScanOptions : AgentResolvePlayerOptions, AgentAutoTrackOpts
---@field windowTitle? string
---@field title? string
---@field search? string
---@field openOnly? boolean
---@field visibleOnly? boolean
---@field maxDepth? integer
---@field maxNodes? integer
---@field flat? boolean
---@field trees? boolean
---@field includeAllElements? boolean

--------------------------------------------------------------------------------
-- Debug log
--------------------------------------------------------------------------------

---@class AgentDebugLogEntry
---@field at integer
---@field lastAt integer
---@field repeatCount integer
---@field side? string
---@field player? string
---@field message string
---@field level integer
---@field levelName string
---@field file? string
---@field line? integer
---@field color AgentColor
---@field seq? integer

---@class AgentDebugLogOptions : AgentResolvePlayerOptions
---@field side? "server"|"client"|"all"
---@field minLevel? integer
---@field limit? integer
---@field sinceSeq? integer
---@field sinceTick? integer
---@field dedupe? boolean

---@class AgentDebugLogSnapshot
---@field entries AgentDebugLogEntry[]
---@field count integer
---@field bufferCount? integer
---@field side string
---@field serverCount? integer
---@field clientCount? integer

--------------------------------------------------------------------------------
-- Event hook
--------------------------------------------------------------------------------

---@class AgentEventElementSummary
---@field type string
---@field name? string

---@class AgentEventHookEntry
---@field at integer
---@field lastAt integer
---@field repeatCount integer
---@field side string
---@field player? string
---@field hookType string
---@field eventName? string
---@field resource? string
---@field source? AgentEventElementSummary
---@field client? AgentEventElementSummary
---@field file? string
---@field line? integer
---@field argCount integer
---@field argPreview? string
---@field seq? integer

---@class AgentEventHookControlOptions : AgentResolvePlayerOptions
---@field side? "server"|"client"|"all"
---@field hookTypes? string[]
---@field nameList? string[]
---@field events? string[]
---@field event? string
---@field action? "start"|"stop"|"clear"|"status"|"list"

---@class AgentEventHookListOptions : AgentResolvePlayerOptions
---@field side? "server"|"client"|"all"
---@field eventName? string
---@field event? string
---@field hookType? string
---@field resource? string
---@field limit? integer
---@field sinceSeq? integer
---@field sinceTick? integer
---@field dedupe? boolean
---@field action? string

---@class AgentEventHookStatus
---@field active boolean
---@field side string
---@field hookTypes string[]
---@field nameList? string[]
---@field startedAt? integer
---@field count integer

---@class AgentEventHookSnapshot
---@field entries AgentEventHookEntry[]
---@field count integer
---@field bufferCount? integer
---@field side string
---@field status AgentEventHookStatus|table
---@field serverCount? integer
---@field clientCount? integer

--------------------------------------------------------------------------------
-- Health
--------------------------------------------------------------------------------

---@class AgentHealthOptions : AgentResolvePlayerOptions
---@field side? "server"|"client"|"all"
---@field networkUsage? boolean
---@field networkUsageLimit? integer
---@field performanceCategory? string
---@field performanceCategories? string[]
---@field performanceOptions? string
---@field performanceFilter? string
---@field listPerformanceCategories? boolean
---@field includeCpu? boolean
---@field includeLuaCpu? boolean
---@field luaCpuLimit? integer

---@class AgentHealthSnapshot
---@field at integer
---@field side? string
---@field player? string
---@field fpsLimit? any
---@field timerCount? integer
---@field memory? table
---@field networkUsage? table
---@field networkStats? any
---@field transferBoxActive? boolean
---@field dx? any
---@field cpu? table
---@field performanceCategories? table
---@field performance? table

--------------------------------------------------------------------------------
-- Resources / async
--------------------------------------------------------------------------------

---@class AgentResourceSearchOptions
---@field query? string
---@field q? string
---@field name? string
---@field state? string
---@field limit? integer
---@field exact? boolean

---@class AgentResourceSnapshot
---@field name string
---@field state string

---@class AgentResourceSearchResult
---@field ok boolean
---@field query string
---@field state? string
---@field count integer
---@field matchedTotal integer
---@field total integer
---@field limit integer
---@field resources AgentResourceSnapshot[]
---@field exactMatch? AgentResourceSnapshot

---@class AgentAsyncRequest
---@field id string
---@field status "pending"|"complete"
---@field player? string
---@field side? string
---@field action? string
---@field options? table
---@field createdAt integer
---@field result? any
---@field error? string
---@field details? any
---@field entry? any
---@field entries? any

---@class AgentClientEvalPlayerResult
---@field player string
---@field ok boolean
---@field result? any
---@field error? string

---@class AgentClientEvalRequest
---@field id string
---@field status "pending"|"complete"
---@field pending integer
---@field resultSlots AgentClientEvalPlayerResult[]|nil
---@field results AgentClientEvalPlayerResult[]|nil
---@field createdAt integer

---@class AgentClientRequestOpts
---@field timeoutMs? integer
---@field onComplete? fun(request: AgentAsyncRequest, clientReturn: any)
