-- NIKHIL'S BUILDING TOOLS: MAINTAINER MAP
-- This file is intentionally annotated line by line at the user's request.
-- Comments describe intent; the executable statements retain the tested logic.
--
-- 1. PURE CORE: C.* helpers below CORE BEGIN/END require no native GUI.
--    Tests extract this block and exercise filtering, sets, hierarchy and limits.
-- 2. WORKING STATE: state points to normal or kit search settings. These are
--    session filters; explicit presets preserve combinations between sessions.
-- 3. SAVED DATABASE: db stores favourites, hidden IDs, recent IDs, presets,
--    categories (path -> ID set), packDescriptions and the global budgetMax.
-- 4. LEGACY IDENTIFIERS: retain the old controller, toolbar and storage IDs.
--    Public filenames/title can change without abandoning existing player data.
-- 5. CATALOGUE: catalog is an ordered metadata array; byId is the loaded-ID map.
--    types/packs are option lists. A source may have zero eligible buildings.
-- 6. FILTER CONTRACT: families combine with AND. Includes within a family form
--    a union; excludes veto. Empty exact sizes match nothing, while empty source,
--    type and wealth includes are unrestricted. Do not merge these semantics.
-- 7. MEMBERSHIP: parent paths include descendants. Stored missing IDs are kept,
--    but loaded-only counts and catalogue filtering suppress ghost list entries.
-- 8. HISTORY: snapshots track only chosen saved fields. The comparison suppresses
--    no-op actions. At most ten Undo and ten Redo actions live in this session.
--    New edits clear Redo. Ordinary filters and city construction are not history.
-- 9. NATIVE HANDOFF: native drawer methods returned by the game use their supplied
--    callable convention. pcall guards optional methods and native failures.
--    Runtime.postpone avoids selecting a drawer while an owned dialog is closing.
--    epoch cancels work when the active city changes; scan revalidates the ID.
-- 10. UI COORDINATES: negative widths/heights use the game's remaining-space
--    convention; negative x/y anchor controls at a far edge. Keep button heights
--    equal for narrow help buttons because native skins may enforce square sizes.
-- 11. LARGE LISTS: building rows and manual lines are recycled fixed-size pools.
--    Logical content extent represents all results; callbacks read slot.item.
--    Never capture an old item directly in a recycled row's callback.
-- 12. GUIDE: guideLines embeds the same manual shipped as a text file, avoiding
--    dependence on an external file-reading API. Rebuild wrapping when editing it.
-- 13. EDIT SAFETY: change public filenames in JSON script references together;
--    keep JSON/manifest comment-free. Run the Lua and package checks after edits.
-- 14. VERIFICATION: automated regression tests use mocked game APIs.
--    also tested this script in TheoTown and confirmed it works in-game.
-- 15. BUGS, CHANGES, SUGGESTIONS, FEEDBACK: Contact me on GitHub - https://github.com/NikhilRasmalla.
--
-- Nikhil's Building Tools. Native placement only; filtering never changes growth.
-- CORE BEGIN: pure data operations, exercised separately by the regression suite.
local C={} -- Namespace for pure data helpers; this block can be tested without a running game.
local unpackArgs=table.unpack or unpack -- Support Lua runtimes that expose unpack under different names.
function C.copy(value) -- Recursively copy saved tables so working state, presets and history never share mutable nested tables.
    if type(value)~='table' then return value end -- Handle a guard/terminal case immediately instead of continuing with unsuitable state.
    local out={}; for k,v in pairs(value) do out[k]=C.copy(v) end; return out -- Keep out local to this scope so callbacks do not accidentally overwrite shared globals.
end -- Close the current function, callback, conditional or loop at this nesting level.
function C.defaults() -- Construct a fresh ordinary filter state; the global budget lives in db separately.
    return {sizeMode='Exact sizes',sizes={['1x1']=true},rotate=false, -- Return the computed value or finish this branch immediately, leaving callers to handle the result.
        minW=1,minH=1,maxW=3,maxH=3,fitW=4,fitH=6, -- Update min W for the current operation; subsequent controls/filters read this state.
        typesIn={},typesOut={},packsIn={},packsOut={},wealth={},customCategories={}, -- Update types In for the current operation; subsequent controls/filters read this state.
        source='All sources',availability='All',collection='All buildings', -- Update source for the current operation; subsequent controls/filters read this state.
        showHidden=false,sort='Name A-Z',query=''} -- Update show Hidden for the current operation; subsequent controls/filters read this state.
end -- Close the current function, callback, conditional or loop at this nesting level.
function C.any(set) for _,v in pairs(set or {}) do if v then return true end end; return false end -- Report whether a set contains any truthy selection; an empty include set often means unrestricted.
function C.count(set) local n=0; for _,v in pairs(set or {}) do if v then n=n+1 end end; return n end -- Count truthy members rather than relying on Lua array length for ID-keyed sets.
function C.choiceSummary(inc,exc,mode) -- Describe the actual effect of empty or non-empty choices for this selector mode.
    local n=C.count(inc);local blocked=C.count(exc) -- Keep n local to this scope so callbacks do not accidentally overwrite shared globals.
    if mode=='memberships' then return n==0 and 'Not assigned to any pack' or ('Assigned to '..n..' personal packs') end -- Handle a guard/terminal case immediately instead of continuing with unsuitable state.
    if mode=='browse' then return n==0 and 'No packs chosen - choose at least one' or ('Browse buildings from '..n..' chosen packs') end -- Handle a guard/terminal case immediately instead of continuing with unsuitable state.
    if mode=='sizes' then return n==0 and 'No sizes chosen - no buildings will match' or ('Only '..n..' chosen footprints allowed') end -- Handle a guard/terminal case immediately instead of continuing with unsuitable state.
    if mode=='wealth' then return n==0 and 'All wealth levels allowed' or ('Only '..n..' chosen wealth levels allowed') end -- Handle a guard/terminal case immediately instead of continuing with unsuitable state.
    local noun=mode=='sources' and 'sources' or 'types' -- Keep noun local to this scope so callbacks do not accidentally overwrite shared globals.
    local allowed=n==0 and ('All '..(blocked>0 and 'other ' or '')..noun..' allowed') or ('Only '..n..' chosen '..(n==1 and noun:sub(1,-2) or noun)) -- Keep allowed local to this scope so callbacks do not accidentally overwrite shared globals.
    return allowed..' | '..(blocked==0 and 'None blocked' or (blocked..' blocked')) -- Return the computed value or finish this branch immediately, leaving callers to handle the result.
end -- Close the current function, callback, conditional or loop at this nesting level.
function C.allowed(key,inc,exc) -- Apply one include/exclude family: explicit exclusion wins; empty includes allow every other key.
    if (exc or {})[key] then return false end -- Reject this candidate or invalid value as soon as the stated requirement fails.
    return not C.any(inc) or inc[key]==true -- Return the computed value or finish this branch immediately, leaving callers to handle the result.
end -- Close the current function, callback, conditional or loop at this nesting level.
function C.size(item,s) -- Match the footprint against exact, range or plot-fit settings, optionally swapping dimensions.
    local w,h=item.w,item.h -- Keep w,h local to this scope so callbacks do not accidentally overwrite shared globals.
    if s.sizeMode=='Any size' then return true end -- Handle a guard/terminal case immediately instead of continuing with unsuitable state.
    if s.sizeMode=='Exact sizes' then -- Run this branch only when its explicit state, selection or availability condition holds.
        return s.sizes[w..'x'..h] or (s.rotate and s.sizes[h..'x'..w]) or false -- Return the computed value or finish this branch immediately, leaving callers to handle the result.
    end -- Close the current function, callback, conditional or loop at this nesting level.
    local function fits(x,y) -- Define the fits callback used by its surrounding screen.
        if s.sizeMode=='Fits within plot' then return x<=s.fitW and y<=s.fitH end -- Handle a guard/terminal case immediately instead of continuing with unsuitable state.
        return x>=s.minW and x<=s.maxW and y>=s.minH and y<=s.maxH -- Return the computed value or finish this branch immediately, leaving callers to handle the result.
    end -- Close the current function, callback, conditional or loop at this nesting level.
    return fits(w,h) or (s.rotate and fits(h,w)) -- Return the computed value or finish this branch immediately, leaving callers to handle the result.
end -- Close the current function, callback, conditional or loop at this nesting level.
function C.inCategory(db,name,id) -- Test direct or descendant membership in a slash-separated personal-pack subtree.
    for path,members in pairs(db.categories or {}) do -- Iterate the indicated entries; ipairs visits ordered rows, while pairs visits ID-keyed maps.
        if (path==name or path:sub(1,#name+1)==name..'/') and members[id] then return true end -- Handle a guard/terminal case immediately instead of continuing with unsuitable state.
    end -- Close the current function, callback, conditional or loop at this nesting level.
    return false -- Return the computed value or finish this branch immediately, leaving callers to handle the result.
end -- Close the current function, callback, conditional or loop at this nesting level.
function C.categoryCount(db,name,known) -- Count unique subtree member IDs; an optional loaded-ID map excludes missing definitions.
    local ids={} -- Keep ids local to this scope so callbacks do not accidentally overwrite shared globals.
    for path,members in pairs(db.categories or {}) do -- Iterate the indicated entries; ipairs visits ordered rows, while pairs visits ID-keyed maps.
        if path==name or path:sub(1,#name+1)==name..'/' then -- Run this branch only when its explicit state, selection or availability condition holds.
            for id,selected in pairs(members) do if selected and (not known or known[id]) then ids[id]=true end end -- Iterate the indicated entries; ipairs visits ordered rows, while pairs visits ID-keyed maps.
        end -- Close the current function, callback, conditional or loop at this nesting level.
    end -- Close the current function, callback, conditional or loop at this nesting level.
    return C.count(ids) -- Return the computed value or finish this branch immediately, leaving callers to handle the result.
end -- Close the current function, callback, conditional or loop at this nesting level.
function C.categoryPath(text) -- Validate and normalise a user-entered personal-pack path without changing the saved database.
    local parts={}; text=tostring(text or '') -- Keep parts local to this scope so callbacks do not accidentally overwrite shared globals.
    if #text>120 or text=='' then return nil,'Use a name up to 120 characters.' end -- Handle a guard/terminal case immediately instead of continuing with unsuitable state.
    for part in (text..'/'):gmatch('(.-)/') do -- Iterate the indicated entries; ipairs visits ordered rows, while pairs visits ID-keyed maps.
        part=part:match('^%s*(.-)%s*$') -- Update part for the current operation; subsequent controls/filters read this state.
        if part=='' then return nil,'Category segments cannot be empty.' end -- Handle a guard/terminal case immediately instead of continuing with unsuitable state.
        parts[#parts+1]=part -- Append this validated path segment; the final join creates the canonical slash-separated key.
    end -- Close the current function, callback, conditional or loop at this nesting level.
    if #parts>6 then return nil,'Use up to six category levels.' end -- Handle a guard/terminal case immediately instead of continuing with unsuitable state.
    return table.concat(parts,'/') -- Return the computed value or finish this branch immediately, leaving callers to handle the result.
end -- Close the current function, callback, conditional or loop at this nesting level.
function C.ensureCategory(db,name) -- Create any missing parent folders and the target pack as ID-keyed membership sets.
    db.categories=db.categories or {} -- Update db.categories for the current operation; subsequent controls/filters read this state.
    local path='' -- Keep path local to this scope so callbacks do not accidentally overwrite shared globals.
    for part in name:gmatch('[^/]+') do -- Iterate the indicated entries; ipairs visits ordered rows, while pairs visits ID-keyed maps.
        path=path=='' and part or path..'/'..part -- Update path for the current operation; subsequent controls/filters read this state.
        db.categories[path]=db.categories[path] or {} -- Update db.categories[path] for the current operation; subsequent controls/filters read this state.
    end -- Close the current function, callback, conditional or loop at this nesting level.
end -- Close the current function, callback, conditional or loop at this nesting level.
local function updateCategoryFilters(s,mapping,deleted) -- Rewrite renamed pack paths or remove deleted paths in a working or saved filter state.
    if not s or not s.customCategories then return end -- Handle a guard/terminal case immediately instead of continuing with unsuitable state.
    local out={} -- Keep out local to this scope so callbacks do not accidentally overwrite shared globals.
    for path,value in pairs(s.customCategories) do -- Iterate the indicated entries; ipairs visits ordered rows, while pairs visits ID-keyed maps.
        if value and not (deleted and deleted[path]) then out[mapping and mapping[path] or path]=true end -- Run this branch only when its explicit state, selection or availability condition holds.
    end -- Close the current function, callback, conditional or loop at this nesting level.
    s.customCategories=out -- Update s.custom Categories for the current operation; subsequent controls/filters read this state.
end -- Close the current function, callback, conditional or loop at this nesting level.
function C.renameCategory(db,old,new,state) -- Move a personal-pack subtree, descriptions and filter references after validating the destination.
    if old==new then return true end -- Handle a guard/terminal case immediately instead of continuing with unsuitable state.
    if new:sub(1,#old+1)==old..'/' then return false,'Cannot move a category inside itself.' end -- Reject this candidate or invalid value as soon as the stated requirement fails.
    local mapping,changes={},{} -- Keep mapping,changes local to this scope so callbacks do not accidentally overwrite shared globals.
    for path,members in pairs(db.categories) do -- Iterate the indicated entries; ipairs visits ordered rows, while pairs visits ID-keyed maps.
        if path==old or path:sub(1,#old+1)==old..'/' then -- Run this branch only when its explicit state, selection or availability condition holds.
            local target=new..path:sub(#old+1) -- Keep target local to this scope so callbacks do not accidentally overwrite shared globals.
            if db.categories[target] then return false,'A category with that name already exists.' end -- Reject this candidate or invalid value as soon as the stated requirement fails.
            mapping[path]=target; changes[path]=members -- Update mapping[path] for the current operation; subsequent controls/filters read this state.
        end -- Close the current function, callback, conditional or loop at this nesting level.
    end -- Close the current function, callback, conditional or loop at this nesting level.
    local descriptions={} -- Keep descriptions local to this scope so callbacks do not accidentally overwrite shared globals.
    for path in pairs(changes) do -- Iterate the indicated entries; ipairs visits ordered rows, while pairs visits ID-keyed maps.
        descriptions[mapping[path]]=(db.packDescriptions or {})[path] -- Update descriptions[mapping[path]] for the current operation; subsequent controls/filters read this state.
        if db.packDescriptions then db.packDescriptions[path]=nil end -- Run this branch only when its explicit state, selection or availability condition holds.
        db.categories[path]=nil -- Update db.categories[path] for the current operation; subsequent controls/filters read this state.
    end -- Close the current function, callback, conditional or loop at this nesting level.
    db.packDescriptions=db.packDescriptions or {} -- Update db.pack Descriptions for the current operation; subsequent controls/filters read this state.
    for path,text in pairs(descriptions) do db.packDescriptions[path]=text end -- Iterate the indicated entries; ipairs visits ordered rows, while pairs visits ID-keyed maps.
    for path,members in pairs(changes) do db.categories[mapping[path]]=members; C.ensureCategory(db,mapping[path]) end -- Iterate the indicated entries; ipairs visits ordered rows, while pairs visits ID-keyed maps.
    updateCategoryFilters(state,mapping) -- Rewrite active personal-pack restrictions to the newly renamed subtree paths.
    for _,preset in pairs(db.presets or {}) do updateCategoryFilters(preset,mapping) end -- Iterate the indicated entries; ipairs visits ordered rows, while pairs visits ID-keyed maps.
    return true,nil,mapping -- Return the computed value or finish this branch immediately, leaving callers to handle the result.
end -- Close the current function, callback, conditional or loop at this nesting level.
function C.deleteCategory(db,name,state) -- Delete only the chosen personal-pack subtree and its references, never original building assets.
    local deleted={} -- Keep deleted local to this scope so callbacks do not accidentally overwrite shared globals.
    for path in pairs(db.categories) do -- Iterate the indicated entries; ipairs visits ordered rows, while pairs visits ID-keyed maps.
        if path==name or path:sub(1,#name+1)==name..'/' then deleted[path]=true end -- Run this branch only when its explicit state, selection or availability condition holds.
    end -- Close the current function, callback, conditional or loop at this nesting level.
    for path in pairs(deleted) do db.categories[path]=nil; if db.packDescriptions then db.packDescriptions[path]=nil end end -- Iterate the indicated entries; ipairs visits ordered rows, while pairs visits ID-keyed maps.
    updateCategoryFilters(state,nil,deleted) -- Remove deleted pack paths from the active restriction set.
    for _,preset in pairs(db.presets or {}) do updateCategoryFilters(preset,nil,deleted) end -- Iterate the indicated entries; ipairs visits ordered rows, while pairs visits ID-keyed maps.
end -- Close the current function, callback, conditional or loop at this nesting level.
function C.setPackMember(db,name,id,value) -- Set or clear direct membership for one building ID in an existing personal pack.
    if not db.categories[name] then return false end -- Reject this candidate or invalid value as soon as the stated requirement fails.
    db.categories[name][id]=value and true or nil -- Update db.categories[name][id] for the current operation; subsequent controls/filters read this state.
    return true -- Return the computed value or finish this branch immediately, leaving callers to handle the result.
end -- Close the current function, callback, conditional or loop at this nesting level.
function C.addToPack(db,name,items) -- Add all candidate IDs to a personal pack, deduplicating and returning the newly added count.
    local added=0 -- Keep added local to this scope so callbacks do not accidentally overwrite shared globals.
    if not db.categories[name] then return 0 end -- Handle a guard/terminal case immediately instead of continuing with unsuitable state.
    for _,item in ipairs(items) do -- Iterate the indicated entries; ipairs visits ordered rows, while pairs visits ID-keyed maps.
        if not db.categories[name][item.id] then added=added+1 end -- Run this branch only when its explicit state, selection or availability condition holds.
        db.categories[name][item.id]=true -- Update db.categories[name][item.id] for the current operation; subsequent controls/filters read this state.
    end -- Close the current function, callback, conditional or loop at this nesting level.
    return added -- Return the computed value or finish this branch immediately, leaving callers to handle the result.
end -- Close the current function, callback, conditional or loop at this nesting level.
function C.matches(item,s,db,available,ignoreQuery) -- Apply all independent filter families with AND; return false immediately on any failed requirement.
    if db.budgetMax~=nil and (type(item.price)~='number' or item.price>db.budgetMax) then return false end -- Reject this candidate or invalid value as soon as the stated requirement fails.
    if not C.size(item,s) then return false end -- Reject this candidate or invalid value as soon as the stated requirement fails.
    if C.any(s.customCategories) then -- Run this branch only when its explicit state, selection or availability condition holds.
        local matched=false -- Keep matched local to this scope so callbacks do not accidentally overwrite shared globals.
        for path,selected in pairs(s.customCategories) do -- Iterate the indicated entries; ipairs visits ordered rows, while pairs visits ID-keyed maps.
            if selected and C.inCategory(db,path,item.id) then matched=true; break end -- Run this branch only when its explicit state, selection or availability condition holds.
        end -- Close the current function, callback, conditional or loop at this nesting level.
        if not matched then return false end -- Reject this candidate or invalid value as soon as the stated requirement fails.
    end -- Close the current function, callback, conditional or loop at this nesting level.
    if not C.allowed(item.kind,s.typesIn,s.typesOut) then return false end -- Reject this candidate or invalid value as soon as the stated requirement fails.
    if not C.allowed(item.pack,s.packsIn,s.packsOut) then return false end -- Reject this candidate or invalid value as soon as the stated requirement fails.
    if s.source=='Built-in only' and item.plugin then return false end -- Reject this candidate or invalid value as soon as the stated requirement fails.
    if s.source=='Plugins only' and not item.plugin then return false end -- Reject this candidate or invalid value as soon as the stated requirement fails.
    if C.any(s.wealth) and (not item.rci or not s.wealth[tostring(item.level)]) then return false end -- Reject this candidate or invalid value as soon as the stated requirement fails.
    if s.heightMin and (not item.height or item.height<s.heightMin) then return false end -- Reject this candidate or invalid value as soon as the stated requirement fails.
    if s.heightMax and (not item.height or item.height>s.heightMax) then return false end -- Reject this candidate or invalid value as soon as the stated requirement fails.
    local hidden=db.hidden[item.id]==true -- Keep hidden local to this scope so callbacks do not accidentally overwrite shared globals.
    if s.collection=='Hidden items' then if not hidden then return false end -- Reject this candidate or invalid value as soon as the stated requirement fails.
    elseif hidden and not s.showHidden then return false end -- Handle the next mutually exclusive case when preceding conditions did not apply.
    if s.collection=='Favourites' and not db.favourites[item.id] then return false end -- Reject this candidate or invalid value as soon as the stated requirement fails.
    if s.collection=='Recent picks' then -- Run this branch only when its explicit state, selection or availability condition holds.
        local recent=false; for _,id in ipairs(db.recent) do if id==item.id then recent=true; break end end -- Keep recent local to this scope so callbacks do not accidentally overwrite shared globals.
        if not recent then return false end -- Reject this candidate or invalid value as soon as the stated requirement fails.
    end -- Close the current function, callback, conditional or loop at this nesting level.
    if s.availability~='All' then -- Run this branch only when its explicit state, selection or availability condition holds.
        local ok=available(item) -- Keep ok local to this scope so callbacks do not accidentally overwrite shared globals.
        if s.availability=='Available only' and not ok then return false end -- Reject this candidate or invalid value as soon as the stated requirement fails.
        if s.availability=='Unavailable only' and ok then return false end -- Reject this candidate or invalid value as soon as the stated requirement fails.
    end -- Close the current function, callback, conditional or loop at this nesting level.
    if not ignoreQuery then -- Run this branch only when its explicit state, selection or availability condition holds.
        local q=string.lower(s.query or '') -- Keep q local to this scope so callbacks do not accidentally overwrite shared globals.
        if q~='' and not string.find(string.lower(item.title),q,1,true) -- Run this branch only when its explicit state, selection or availability condition holds.
            and not string.find(string.lower(item.id),q,1,true) then return false end -- Reject text that matches neither the lowercased title nor the lowercased ID; plain=true treats pattern symbols literally.
    end -- Close the current function, callback, conditional or loop at this nesting level.
    return true -- Return the computed value or finish this branch immediately, leaving callers to handle the result.
end -- Close the current function, callback, conditional or loop at this nesting level.
function C.sort(items,mode,db) -- Sort passing metadata with stable name/ID tie-breaks and unknown numeric values placed last.
    local rank={}; for i,id in ipairs(db.recent or {}) do rank[id]=i end -- Keep rank local to this scope so callbacks do not accidentally overwrite shared globals.
    local function less(a,b) -- Define the less callback used by its surrounding screen.
        if mode=='Name Z-A' then -- Run this branch only when its explicit state, selection or availability condition holds.
            local x,y=string.lower(a.title),string.lower(b.title) -- Keep x,y local to this scope so callbacks do not accidentally overwrite shared globals.
            if x~=y then return x>y end -- Handle a guard/terminal case immediately instead of continuing with unsuitable state.
        elseif mode=='Footprint' then if a.w*a.h~=b.w*b.h then return a.w*a.h<b.w*b.h end -- Handle the next mutually exclusive case when preceding conditions did not apply.
        elseif mode=='Height' then -- Handle the next mutually exclusive case when preceding conditions did not apply.
            local x,y=a.height or math.huge,b.height or math.huge; if x~=y then return x<y end -- Keep x,y local to this scope so callbacks do not accidentally overwrite shared globals.
        elseif mode=='Price' then -- Handle the next mutually exclusive case when preceding conditions did not apply.
            local x,y=a.price or math.huge,b.price or math.huge; if x~=y then return x<y end -- Keep x,y local to this scope so callbacks do not accidentally overwrite shared globals.
        elseif mode=='Plugin source' then if a.pack~=b.pack then return a.pack<b.pack end -- Handle the next mutually exclusive case when preceding conditions did not apply.
        elseif mode=='Most recent' then -- Handle the next mutually exclusive case when preceding conditions did not apply.
            local x,y=rank[a.id] or math.huge,rank[b.id] or math.huge; if x~=y then return x<y end -- Keep x,y local to this scope so callbacks do not accidentally overwrite shared globals.
        end -- Close the current function, callback, conditional or loop at this nesting level.
        local x,y=string.lower(a.title),string.lower(b.title) -- Keep x,y local to this scope so callbacks do not accidentally overwrite shared globals.
        if x~=y then return x<y end -- Handle a guard/terminal case immediately instead of continuing with unsuitable state.
        return a.id<b.id -- Return the computed value or finish this branch immediately, leaving callers to handle the result.
    end -- Close the current function, callback, conditional or loop at this nesting level.
    table.sort(items,less); return items -- Order this array with the supplied comparator without modifying original building definitions.
end -- Close the current function, callback, conditional or loop at this nesting level.
function C.filter(catalog,s,db,available,ignoreQuery) -- Build and sort a fresh result array without changing the underlying catalogue.
    local out={}; for _,item in ipairs(catalog) do -- Keep out local to this scope so callbacks do not accidentally overwrite shared globals.
        if C.matches(item,s,db,available,ignoreQuery) then out[#out+1]=item end -- Run this branch only when its explicit state, selection or availability condition holds.
    end -- Close the current function, callback, conditional or loop at this nesting level.
    return C.sort(out,s.sort,db) -- Return the computed value or finish this branch immediately, leaving callers to handle the result.
end -- Close the current function, callback, conditional or loop at this nesting level.
function C.record(db,id) -- Record the latest successful selector activation, deduplicate it and retain at most 100 IDs.
    local out={id}; for _,old in ipairs(db.recent) do -- Keep out local to this scope so callbacks do not accidentally overwrite shared globals.
        if old~=id and #out<100 then out[#out+1]=old end -- Run this branch only when its explicit state, selection or availability condition holds.
    end; db.recent=out -- Finish deduplication and replace the saved recency list with its bounded newest-first copy.
end -- Close the current function, callback, conditional or loop at this nesting level.
function C.random(catalog,s,db,available,random) -- Choose an available favourite that passes all current filters, including the global budget.
    local candidates={}; for _,item in ipairs(C.filter(catalog,s,db,available)) do -- Keep candidates local to this scope so callbacks do not accidentally overwrite shared globals.
        if db.favourites[item.id] and available(item) then candidates[#candidates+1]=item end -- Run this branch only when its explicit state, selection or availability condition holds.
    end -- Close the current function, callback, conditional or loop at this nesting level.
    if #candidates==0 then return nil end -- Handle a guard/terminal case immediately instead of continuing with unsuitable state.
    return candidates[(random or math.random)(#candidates)] -- Return the computed value or finish this branch immediately, leaving callers to handle the result.
end -- Close the current function, callback, conditional or loop at this nesting level.
function C.integer(text,optional,zero) -- Validate plain decimal integers, optional blank bounds and an optional zero allowance.
    text=tostring(text or ''):match('^%s*(.-)%s*$') -- Update text for the current operation; subsequent controls/filters read this state.
    if optional and text=='' then return nil,true end -- Handle a guard/terminal case immediately instead of continuing with unsuitable state.
    if not text:match('^%d+$') then return nil,false end -- Handle a guard/terminal case immediately instead of continuing with unsuitable state.
    local n=tonumber(text) -- Keep n local to this scope so callbacks do not accidentally overwrite shared globals.
    if not n or n<(zero and 0 or 1) or n>2147483647 then return nil,false end -- Handle a guard/terminal case immediately instead of continuing with unsuitable state.
    return math.floor(n),true -- Return the computed value or finish this branch immediately, leaving callers to handle the result.
end -- Close the current function, callback, conditional or loop at this nesting level.
function C.parseSizes(text) -- Parse manual footprint pairs into a deduplicated set, rejecting malformed dimensions.
    local set={}; local n=0 -- Keep set local to this scope so callbacks do not accidentally overwrite shared globals.
    for token in tostring(text):gmatch('[^,;]+') do -- Iterate the indicated entries; ipairs visits ordered rows, while pairs visits ID-keyed maps.
        local x,y=token:match('^%s*(%d+)%s*[xX*]%s*(%d+)%s*$') -- Keep x,y local to this scope so callbacks do not accidentally overwrite shared globals.
        local w,a=C.integer(x); local h,b=C.integer(y) -- Keep w,a local to this scope so callbacks do not accidentally overwrite shared globals.
        if not a or not b then return nil,'Use positive sizes such as 1x1, 2x3, 4x4.' end -- Handle a guard/terminal case immediately instead of continuing with unsuitable state.
        set[w..'x'..h]=true; n=n+1 -- Update set[w..'x'..h] for the current operation; subsequent controls/filters read this state.
    end -- Close the current function, callback, conditional or loop at this nesting level.
    if n==0 then return nil,'Enter at least one size.' end -- Handle a guard/terminal case immediately instead of continuing with unsuitable state.
    return set -- Return the computed value or finish this branch immediately, leaving callers to handle the result.
end -- Close the current function, callback, conditional or loop at this nesting level.
function C.pruneSourceFilters(s,knownPacks,knownTypes) -- Remove unavailable source/type choices from a working state without deleting saved references.
    if not s then return 0 end -- Handle a guard/terminal case immediately instead of continuing with unsuitable state.
    local removed=0 -- Keep removed local to this scope so callbacks do not accidentally overwrite shared globals.
    for _,entry in ipairs({{'packsIn',knownPacks},{'packsOut',knownPacks},{'typesIn',knownTypes},{'typesOut',knownTypes}}) do -- Iterate the indicated entries; ipairs visits ordered rows, while pairs visits ID-keyed maps.
        for key in pairs(s[entry[1]] or {}) do -- Iterate the indicated entries; ipairs visits ordered rows, while pairs visits ID-keyed maps.
            if not entry[2][key] then s[entry[1]][key]=nil;removed=removed+1 end -- Run this branch only when its explicit state, selection or availability condition holds.
        end -- Close the current function, callback, conditional or loop at this nesting level.
    end -- Close the current function, callback, conditional or loop at this nesting level.
    return removed -- Return the computed value or finish this branch immediately, leaving callers to handle the result.
end -- Close the current function, callback, conditional or loop at this nesting level.
function C.normalise(saved) -- Copy recognised preset fields onto defaults so older saved presets remain usable.
    local s=C.defaults(); for k,v in pairs(saved or {}) do if s[k]~=nil or k=='heightMin' or k=='heightMax' then s[k]=C.copy(v) end end -- Keep s local to this scope so callbacks do not accidentally overwrite shared globals.
    return s -- Return the computed value or finish this branch immediately, leaving callers to handle the result.
end -- Close the current function, callback, conditional or loop at this nesting level.
-- CORE END

local state=C.defaults() -- Create the currently active working filter state.
local catalog,types,packs,byId=nil,{},{},{} -- Keep catalog,types,packs,by Id local to this scope so callbacks do not accidentally overwrite shared globals.
local knownPacks,knownTypes={},{} -- Keep known Packs,known Types local to this scope so callbacks do not accidentally overwrite shared globals.
local db={favourites={},hidden={},recent={},presets={},categories={},packDescriptions={}} -- Keep db local to this scope so callbacks do not accidentally overwrite shared globals.
local activeDialog=nil -- Track only the tool-owned main dialog so navigation can close it safely.
local inCity=false -- Gate native placement until a city is active.
local epoch=0 -- Generation counter used to cancel deferred work after a city transition.
local buttonId='$tenjiku_size_picker_button_v1' -- Preserve the owned toolbar ID for duplicate prevention and cleanup across upgrades.
local storageKey='$tenjiku_size_picker_v7' -- Preserve the existing persistent-storage key so the public rename does not abandon saved data.
local showHome,showMain,browse,categoryManager,categoryEditor,assignCategories,showGuide -- Keep show Home,show Main,browse,category Manager,category Editor,assign Categories,show Guide local to this scope so callbacks do not accidentally overwrite shared globals.
local editingPack=nil -- No personal-pack membership editor is active initially.
local editingReturnState=nil -- Reserve a copy of the kit state to restore after membership editing.
local advancedOpen=false -- Keep advanced filter controls collapsed on initial entry; hiding them does not clear their values.
local currentMode='normal' -- Track which mode determines row actions and filter-state ownership.
local normalState=state -- Retain normal-mode filters while the kit owns the active state.
local kitState=C.defaults();kitState.sizeMode='Any size' -- Start kit browsing unrestricted by footprint and retain its state independently.
local function call(object,name,fallback,...) -- Invoke an optional draft method defensively and return a safe fallback on failure or nil.
    local args={...} -- Keep args local to this scope so callbacks do not accidentally overwrite shared globals.
    local ok,v=pcall(function() return object[name](object,unpackArgs(args)) end) -- Protect the native/API operation so a failed method can be handled without aborting the tool.
    if ok and v~=nil then return v end; return fallback -- Handle a guard/terminal case immediately instead of continuing with unsuitable state.
end -- Close the current function, callback, conditional or loop at this nesting level.
local helpDialog -- Keep help Dialog local to this scope so callbacks do not accidentally overwrite shared globals.
local function dismiss() -- Close help and the current owned dialog, clearing references before a replacement screen opens.
    if helpDialog then pcall(helpDialog.close);helpDialog=nil end -- Protect the native/API operation so a failed method can be handled without aborting the tool.
    if activeDialog then local d=activeDialog; activeDialog=nil; pcall(d.close) end -- Protect the native/API operation so a failed method can be handled without aborting the tool.
end -- Close the current function, callback, conditional or loop at this nesting level.
-- Help stays above the current screen, preserving searches and unsaved fields.
local function explain(title,text) -- Open a small help overlay while keeping the underlying screen and its input state intact.
    if helpDialog then pcall(helpDialog.close) end -- Protect the native/API operation so a failed method can be handled without aborting the tool.
    local d -- Keep d local to this scope so callbacks do not accidentally overwrite shared globals.
    d=GUI.createDialog{title=title,width=420,height=230,text=text, -- Create this screen with an explicit title and bounded dimensions, then retain its owned handle.
        actions={{text='Got it',onClick=function() if d then pcall(d.close) end;helpDialog=nil end}}} -- Protect the native/API operation so a failed method can be handled without aborting the tool.
    helpDialog=d -- Update help Dialog for the current operation; subsequent controls/filters read this state.
end -- Close the current function, callback, conditional or loop at this nesting level.
local helpTopics={ -- Keep help Topics local to this scope so callbacks do not accidentally overwrite shared globals.
    ['Theons budget']='Set one maximum listed price for BOTH modes, pack browsing, bulk additions and random favourites. Unlimited removes the cap. Unknown prices are excluded under a cap. Actual charges follow game rules. Your wallet has hired a bouncer.', -- Store the contextual-help explanation for this control; the question-mark overlay reads this text.
    ['Size']='Choose exact footprints, several sizes, a range, or anything that fits your plot. X and Y count tiles. Tiny plot, big ambitions.', -- Store the contextual-help explanation for this control; the question-mark overlay reads this text.
    ['Types']='Include the building types you want; exclude the ones you do not. Empty includes means every type. Excludes get the final veto.', -- Store the contextual-help explanation for this control; the question-mark overlay reads this text.
    ['Installed plugins']='Filter by installed source plugin packs. These are downloaded sources, not your personal collections. Your downloads have entered the chat.', -- Store the contextual-help explanation for this control; the question-mark overlay reads this text.
    ['Source']='Choose built-in buildings, plugin buildings, or both. Vanilla, toppings, or the whole sundae.', -- Store the contextual-help explanation for this control; the question-mark overlay reads this text.
    ['Name / ID']='Find text inside building names, IDs and catalogue metadata. Clear it to let everybody back into the party.', -- Store the contextual-help explanation for this control; the question-mark overlay reads this text.
    ['More filters']='Reveal wealth, height, favourites, availability, sorting and presets. The nerd cupboard is unlocked.', -- Store the contextual-help explanation for this control; the question-mark overlay reads this text.
    ['Fewer filters']='Fold the extra controls away. Their settings still apply. Tidier desk, same paperwork.', -- Store the contextual-help explanation for this control; the question-mark overlay reads this text.
    ['Include swapped dimensions']='Also accept the footprint the other way round: 2x3 can match 3x2. This finds candidates; it does not rotate buildings for you. Plot twist.', -- Store the contextual-help explanation for this control; the question-mark overlay reads this text.
    ['Wealth']='Filter RCI wealth: T, TT or TTT. Choose several, or leave empty for any level. Fancy walls are still walls.', -- Store the contextual-help explanation for this control; the question-mark overlay reads this text.
    ['Visual height']='Limit the height reported by the game, in game units, not floors. Unknown heights cannot satisfy a limit. Skyscrapers, mind your head.', -- Store the contextual-help explanation for this control; the question-mark overlay reads this text.
    ['Collection']='Browse all buildings, favourites, recent picks or hidden items. Recent means chosen in this picker, not confirmed construction. Your architectural diary.', -- Store the contextual-help explanation for this control; the question-mark overlay reads this text.
    ['Availability']='Use the game placement check to show available or unavailable buildings. Placement rules still apply at the chosen tile. The mayor cannot bribe this button.', -- Store the contextual-help explanation for this control; the question-mark overlay reads this text.
    ['Show hidden items']='Let hidden buildings appear in ordinary results again. Hide only affects this picker. Nobody bulldozed anything.', -- Store the contextual-help explanation for this control; the question-mark overlay reads this text.
    ['Sort']='Order matching buildings by name, footprint, height, price, source or recency. Same guests, different queue.', -- Store the contextual-help explanation for this control; the question-mark overlay reads this text.
    ['Presets']='Save or reload a filter combination. A preset remembers a search, not a handpicked building collection. A bookmark for your brain.', -- Store the contextual-help explanation for this control; the question-mark overlay reads this text.
    ['Finish adding buildings']='Return to the pack editor. Add and Remove changes are already saved as you click. No dramatic Save button finale.', -- Store the contextual-help explanation for this control; the question-mark overlay reads this text.
    ['Back to your building packs']='Return to your personal named collections. Your district wardrobe awaits.', -- Store the contextual-help explanation for this control; the question-mark overlay reads this text.
    ['Browse all buildings in pack']='Show this pack and its subpacks, then use Build to place a building. It does not change zoned growth. You are the casting director.', -- Store the contextual-help explanation for this control; the question-mark overlay reads this text.
    ['Browse pack by building type']='Browse one building type inside this pack, including subpacks. Shops with shops; chimneys with chimneys.', -- Store the contextual-help explanation for this control; the question-mark overlay reads this text.
    ['Add / remove buildings']='Open the catalogue with optional filters. Add saves a building reference; Remove takes it out of this pack. No asset cloning machine involved.', -- Store the contextual-help explanation for this control; the question-mark overlay reads this text.
    ['Add all current filtered matches']='Add every current match, including those below the visible rows. Filters decide the guest list. Check them before inviting the whole city.', -- Store the contextual-help explanation for this control; the question-mark overlay reads this text.
    ['Edit pack name / description']='Rename this collection and write a short description. Use slashes for subpacks, like Japan/Homes. Filing cabinets, but fashionable.', -- Store the contextual-help explanation for this control; the question-mark overlay reads this text.
    ['Delete pack and subpacks']='Remove this personal collection and its subpacks. Installed buildings stay installed. Only the playlist gets shredded.' -- Store the contextual-help explanation for this control; the question-mark overlay reads this text.
} -- Finish the current table or GUI/API argument block.
local function helpButton(parent,args,title,message) -- Attach a question-mark control that opens the supplied topic explanation.
    args.text='?';args.onClick=function() explain(title,message) end -- Handle this button click using its supplied closure; capture the current item/state before acting.
    return parent:addButton(args) -- Create an actionable GUI button with the specified placement, label and callback.
end -- Close the current function, callback, conditional or loop at this nesting level.
local function helpFor(label) -- Choose contextual help by a row-label prefix, with a safe fallback for unmatched controls.
    for key,message in pairs(helpTopics) do -- Iterate the indicated entries; ipairs visits ordered rows, while pairs visits ID-keyed maps.
        if label:sub(1,#key)==key then return key,message end -- Handle a guard/terminal case immediately instead of continuing with unsuitable state.
    end -- Close the current function, callback, conditional or loop at this nesting level.
    return label,'Choose this option to continue. The buildings are waiting politely.' -- Return the computed value or finish this branch immediately, leaving callers to handle the result.
end -- Close the current function, callback, conditional or loop at this nesting level.
local undoStack,redoStack={},{} -- Keep undo Stack,redo Stack local to this scope so callbacks do not accidentally overwrite shared globals.
local historyKeys={'favourites','hidden','presets','categories','packDescriptions','budgetMax'} -- Keep history Keys local to this scope so callbacks do not accidentally overwrite shared globals.
local lastSaved=nil -- Keep last Saved local to this scope so callbacks do not accidentally overwrite shared globals.
local function snapshot() -- Copy only undoable data fields; recent picks and working filter navigation are intentionally excluded.
    local out={};for _,key in ipairs(historyKeys) do out[key]=C.copy(db[key]) end;return out -- Keep out local to this scope so callbacks do not accidentally overwrite shared globals.
end -- Close the current function, callback, conditional or loop at this nesting level.
local function equal(a,b) -- Compare nested saved-data values so unchanged data does not consume an undo step.
    if type(a)~=type(b) then return false end -- Reject this candidate or invalid value as soon as the stated requirement fails.
    if type(a)~='table' then return a==b end -- Handle a guard/terminal case immediately instead of continuing with unsuitable state.
    for k,v in pairs(a) do if not equal(v,b[k]) then return false end end -- Iterate the indicated entries; ipairs visits ordered rows, while pairs visits ID-keyed maps.
    for k in pairs(b) do if a[k]==nil then return false end end -- Iterate the indicated entries; ipairs visits ordered rows, while pairs visits ID-keyed maps.
    return true -- Return the computed value or finish this branch immediately, leaving callers to handle the result.
end -- Close the current function, callback, conditional or loop at this nesting level.
local function persist() -- Capture a changed data snapshot, bound Undo to ten, clear Redo on edits, and write game storage.
    local now=snapshot() -- Keep now local to this scope so callbacks do not accidentally overwrite shared globals.
    if lastSaved and not equal(now,lastSaved) then -- Run this branch only when its explicit state, selection or availability condition holds.
        undoStack[#undoStack+1]=lastSaved -- Push the previous saved snapshot before accepting the new changed state.
        if #undoStack>10 then table.remove(undoStack,1) end -- Run this branch only when its explicit state, selection or availability condition holds.
        redoStack={} -- Update redo Stack for the current operation; subsequent controls/filters read this state.
    end -- Close the current function, callback, conditional or loop at this nesting level.
    lastSaved=now -- Update last Saved for the current operation; subsequent controls/filters read this state.
    local ok,root=pcall(TheoTown.getStorage) -- Protect the native/API operation so a failed method can be handled without aborting the tool.
    if ok and type(root)=='table' then root[storageKey]=C.copy(db) end -- Run this branch only when its explicit state, selection or availability condition holds.
end -- Close the current function, callback, conditional or loop at this nesting level.
local function historyStep(from,to,back) -- Restore one history snapshot, populate the opposite stack, repair stale UI references and redraw.
    if #from==0 then Debug.toast('Nothing to rewind. The timeline is behaving.');return end -- Explain the result or validation issue through a short in-game message.
    to[#to+1]=snapshot() -- Push the current state onto the opposite history stack before restoring the selected snapshot.
    if #to>10 then table.remove(to,1) end -- Run this branch only when its explicit state, selection or availability condition holds.
    local target=table.remove(from) -- Keep target local to this scope so callbacks do not accidentally overwrite shared globals.
    for _,key in ipairs(historyKeys) do db[key]=C.copy(target[key]) end -- Iterate the indicated entries; ipairs visits ordered rows, while pairs visits ID-keyed maps.
    lastSaved=snapshot();persist() -- Commit the changed picker data and capture an undo step only if tracked data actually changed.
    if editingPack and not db.categories[editingPack] then editingPack=nil;editingReturnState=nil end -- Run this branch only when its explicit state, selection or availability condition holds.
    -- An old pack filter must not silently turn into an unfiltered catalogue.
    for name in pairs(state.customCategories or {}) do -- Iterate the indicated entries; ipairs visits ordered rows, while pairs visits ID-keyed maps.
        if not db.categories[name] then state.customCategories[name]=nil end -- Run this branch only when its explicit state, selection or availability condition holds.
    end -- Close the current function, callback, conditional or loop at this nesting level.
    (back or showHome)() -- Redraw the requesting screen after history restoration; default to Home when no callback was supplied.
end -- Close the current function, callback, conditional or loop at this nesting level.
local function historyButtons(parent,y,back,x) -- Create Undo, Redo and scope-help controls for the current screen.
    x=x or 150 -- Update x for the current operation; subsequent controls/filters read this state.
    parent:addButton{x=x,y=y,width=86,height=28,text='Undo',onClick=function() historyStep(undoStack,redoStack,back) end} -- Create an actionable GUI button with the specified placement, label and callback.
    parent:addButton{x=x+92,y=y,width=86,height=28,text='Redo',onClick=function() historyStep(redoStack,undoStack,back) end} -- Create an actionable GUI button with the specified placement, label and callback.
    helpButton(parent,{x=x+184,y=y,width=28,height=28},'Undo / Redo','Reverse the last 10 picker data edits this session: pack membership, names, descriptions, favourites, hidden items, presets and budget. New edits clear Redo. Filter navigation and city construction are not rewound. A tiny time machine, with boundaries.') -- Provide contextual help using a small square button and the matching topic description.
end -- Close the current function, callback, conditional or loop at this nesting level.
local function loadData() -- Restore existing game-wide saved data using the legacy key retained through the public rename.
    local ok,root=pcall(TheoTown.getStorage) -- Protect the native/API operation so a failed method can be handled without aborting the tool.
    if ok and type(root)=='table' and type(root[storageKey])=='table' then -- Run this branch only when its explicit state, selection or availability condition holds.
        local saved=root[storageKey] -- Keep saved local to this scope so callbacks do not accidentally overwrite shared globals.
        local cap,valid=C.integer(saved.budgetMax,true,true) -- Keep cap,valid local to this scope so callbacks do not accidentally overwrite shared globals.
        if valid then db.budgetMax=cap end -- Run this branch only when its explicit state, selection or availability condition holds.
        for _,key in ipairs({'favourites','hidden','recent','presets','categories','packDescriptions'}) do -- Iterate the indicated entries; ipairs visits ordered rows, while pairs visits ID-keyed maps.
            if type(saved[key])=='table' then db[key]=C.copy(saved[key]) end -- Run this branch only when its explicit state, selection or availability condition holds.
        end -- Close the current function, callback, conditional or loop at this nesting level.
    end -- Close the current function, callback, conditional or loop at this nesting level.
    lastSaved=snapshot() -- Update last Saved for the current operation; subsequent controls/filters read this state.
end -- Close the current function, callback, conditional or loop at this nesting level.
local function toggle(set,id) if set[id] then set[id]=nil else set[id]=true end; persist() end -- Toggle a favourite/hidden ID in its saved set and persist the resulting data change.
local function drawer(item) -- Create TheoTown's native selector under pcall; the tool never directly constructs a building.
    local ok,value=pcall(City.createDraftDrawer,item.draft,true) -- Protect the native/API operation so a failed method can be handled without aborting the tool.
    return ok and value or nil -- Return the computed value or finish this branch immediately, leaving callers to handle the result.
end -- Close the current function, callback, conditional or loop at this nesting level.
local function available(item) -- Check native selector availability defensively; this can be more expensive than metadata filtering.
    local d=drawer(item); if not d then return false end -- Keep d local to this scope so callbacks do not accidentally overwrite shared globals.
    local ok,value=pcall(d.isSelectable); return ok and value==true -- Protect the native/API operation so a failed method can be handled without aborting the tool.
end -- Close the current function, callback, conditional or loop at this nesting level.
local function scan() -- Rebuild loaded building/source metadata and prune obsolete active source/type filters.
    catalog,types,packs,byId={},{},{},{} -- Clear all cached catalogue arrays/maps before rebuilding them from currently loaded drafts.
    local typeMap,packMap={},{} -- Keep type Map,pack Map local to this scope so callbacks do not accidentally overwrite shared globals.
    for _,draft in ipairs(Draft.getDrafts()) do -- Iterate the indicated entries; ipairs visits ordered rows, while pairs visits ID-keyed maps.
        pcall(function() -- Protect the native/API operation so a failed method can be handled without aborting the tool.
            if draft:isLoaded() and draft:isPlugin() then -- Run this branch only when its explicit state, selection or availability condition holds.
                local id=tonumber(draft:getPluginId()) or 0 -- Keep id local to this scope so callbacks do not accidentally overwrite shared globals.
                local key=id>0 and tostring(id) or 'local' -- Keep key local to this scope so callbacks do not accidentally overwrite shared globals.
                if not packMap[key] then packMap[key]={key=key,storeId=id,count=0,example=draft:getTitle() or draft:getId()} end -- Run this branch only when its explicit state, selection or availability condition holds.
            end -- Close the current function, callback, conditional or loop at this nesting level.
        end) -- Close the current function, callback, conditional or loop at this nesting level.
        local ok,item=pcall(function() -- Protect the native/API operation so a failed method can be handled without aborting the tool.
            if not draft:isBuilding() or draft:isTemplate() or not draft:isLoaded() or not draft:isVisible() then return nil end -- Handle a guard/terminal case immediately instead of continuing with unsuitable state.
            local w,h=draft:getWidth(),draft:getHeight() -- Keep w,h local to this scope so callbacks do not accidentally overwrite shared globals.
            if not w or not h or w<1 or h<1 then return nil end -- Handle a guard/terminal case immediately instead of continuing with unsuitable state.
            local raw=draft:getType() or 'building' -- Keep raw local to this scope so callbacks do not accidentally overwrite shared globals.
            local kind=raw:gsub('(%a)([%w_]*)',function(a,b) return a:upper()..b end) -- Keep kind local to this scope so callbacks do not accidentally overwrite shared globals.
            local plugin=draft:isPlugin() -- Keep plugin local to this scope so callbacks do not accidentally overwrite shared globals.
            local pid=plugin and (tonumber(draft:getPluginId()) or 0) or 0 -- Keep pid local to this scope so callbacks do not accidentally overwrite shared globals.
            local key=plugin and (pid>0 and tostring(pid) or 'local') or 'builtin' -- Keep key local to this scope so callbacks do not accidentally overwrite shared globals.
            local rci=call(draft,'isRCI',false) -- Keep rci local to this scope so callbacks do not accidentally overwrite shared globals.
            local level=rci and tonumber(call(draft,'getLevel',nil)) or nil -- Keep level local to this scope so callbacks do not accidentally overwrite shared globals.
            local id=draft:getId() -- Keep id local to this scope so callbacks do not accidentally overwrite shared globals.
            return {id=id,draft=draft,w=w,h=h,title=draft:getTitle() or id,kind=kind, -- Return the computed value or finish this branch immediately, leaving callers to handle the result.
                plugin=plugin,pack=key,level=level,rci=rci, -- Update plugin for the current operation; subsequent controls/filters read this state.
                height=tonumber(call(draft,'getBuildHeight',nil)),price=tonumber(call(draft,'getPrice',nil))} -- Update height for the current operation; subsequent controls/filters read this state.
        end) -- Close the current function, callback, conditional or loop at this nesting level.
        if ok and item then -- Run this branch only when its explicit state, selection or availability condition holds.
            catalog[#catalog+1]=item; byId[item.id]=item; typeMap[item.kind]=true -- Register the eligible definition in the ordered catalogue, direct ID lookup and discovered-type set.
            local p=packMap[item.pack] -- Keep p local to this scope so callbacks do not accidentally overwrite shared globals.
            if p then p.count=p.count+1; if p.count==1 then p.example=item.title end end -- Run this branch only when its explicit state, selection or availability condition holds.
        end -- Close the current function, callback, conditional or loop at this nesting level.
    end -- Close the current function, callback, conditional or loop at this nesting level.
    for kind in pairs(typeMap) do types[#types+1]={key=kind,label=kind} end -- Iterate the indicated entries; ipairs visits ordered rows, while pairs visits ID-keyed maps.
    table.sort(types,function(a,b) return a.label<b.label end) -- Order this array with the supplied comparator without modifying original building definitions.
    packs[1]={key='builtin',label='Built-in game buildings'} -- Update packs[1] for the current operation; subsequent controls/filters read this state.
    for _,p in pairs(packMap) do -- Iterate the indicated entries; ipairs visits ordered rows, while pairs visits ID-keyed maps.
        p.label=p.key=='local' and ('Local ZIP / unidentified packs ('..p.count..' buildings)') -- Update p.label for the current operation; subsequent controls/filters read this state.
            or ('Store #'..p.storeId..' | e.g. '..p.example..' ('..p.count..' buildings)') -- Label a store source with its stable numeric ID, an explicitly illustrative title and eligible-building count.
        packs[#packs+1]=p -- Append the discovered source metadata to the selector option array.
    end -- Close the current function, callback, conditional or loop at this nesting level.
    table.sort(packs,function(a,b) return a.key<b.key end) -- Order this array with the supplied comparator without modifying original building definitions.
    knownPacks={};knownTypes=typeMap -- Update known Packs for the current operation; subsequent controls/filters read this state.
    for _,entry in ipairs(packs) do knownPacks[entry.key]=true end -- Iterate the indicated entries; ipairs visits ordered rows, while pairs visits ID-keyed maps.
    local removed=0 -- Keep removed local to this scope so callbacks do not accidentally overwrite shared globals.
    local visited={} -- Keep visited local to this scope so callbacks do not accidentally overwrite shared globals.
    for _,candidate in pairs({state,normalState,kitState,editingReturnState}) do -- Iterate the indicated entries; ipairs visits ordered rows, while pairs visits ID-keyed maps.
        if not visited[candidate] then visited[candidate]=true;removed=removed+C.pruneSourceFilters(candidate,knownPacks,knownTypes) end -- Run this branch only when its explicit state, selection or availability condition holds.
    end -- Close the current function, callback, conditional or loop at this nesting level.
    if removed>0 then Debug.toast('Removed filters for missing sources or building types. Remaining filters still apply.') end -- Explain the result or validation issue through a short in-game message.
end -- Close the current function, callback, conditional or loop at this nesting level.
local function getResults(ignoreQuery) -- Ensure a catalogue exists, sanitise working source/type choices and run the combined filters.
    if not catalog then scan() end -- Run this branch only when its explicit state, selection or availability condition holds.
    C.pruneSourceFilters(state,knownPacks,knownTypes) -- Delegate this operation to the pure data helper so UI actions share the same validated behaviour.
    return C.filter(catalog,state,db,available,ignoreQuery) -- Return the computed value or finish this branch immediately, leaving callers to handle the result.
end -- Close the current function, callback, conditional or loop at this nesting level.
local function scrollbar(parent,id,getList,getExtent,y,bottom) -- Create a visible draggable thumb linked to a list's shift and its full logical content extent.
    local function metrics(self) -- Calculate viewport size, thumb height and legal scrolling range for the linked list.
        local list=getList(); local h=math.max(1,self:getHeight()) -- Keep list local to this scope so callbacks do not accidentally overwrite shared globals.
        local view=list and math.max(1,list:getClientHeight()) or h -- Keep view local to this scope so callbacks do not accidentally overwrite shared globals.
        local total=math.max(view,getExtent()) -- Keep total local to this scope so callbacks do not accidentally overwrite shared globals.
        return list,h,math.min(h,math.max(20,h*view/total)),math.max(0,total-view) -- Return the computed value or finish this branch immediately, leaving callers to handle the result.
    end -- Close the current function, callback, conditional or loop at this nesting level.
    return parent:addCanvas{id=id,x=-16,y=y or 62,width=14,height=-(bottom or 42), -- Create a layout/content container; its logical dimensions can exceed the visible viewport.
        onDraw=function(self,x,yy,w,h) -- Define the on Draw callback used by its surrounding screen.
            local list,_,thumb,range=metrics(self) -- Keep list, ,thumb,range local to this scope so callbacks do not accidentally overwrite shared globals.
            local fraction=range>0 and math.min(1,math.abs(list:getShiftY())/range) or 0 -- Keep fraction local to this scope so callbacks do not accidentally overwrite shared globals.
            Drawing.setColor(42,48,57); Drawing.drawRect(x,yy,w,h) -- Draw or reset the custom scrollbar skin; no city simulation data is changed.
            Drawing.setColor(175,190,205); Drawing.drawRect(x+2,yy+(h-thumb)*fraction,w-4,thumb); Drawing.reset() -- Draw or reset the custom scrollbar skin; no city simulation data is changed.
        end, -- Close the current function, callback, conditional or loop at this nesting level.
        onUpdate=function(self) -- Define the on Update callback used by its surrounding screen.
            local _,touch=self:getTouchPoint(); if not touch then return end -- Keep ,touch local to this scope so callbacks do not accidentally overwrite shared globals.
            local list,h,thumb,range=metrics(self); if not list or range<=0 then return end -- Keep list,h,thumb,range local to this scope so callbacks do not accidentally overwrite shared globals.
            local fraction=math.max(0,math.min(1,(touch-self:getAbsoluteY()-thumb/2)/math.max(1,h-thumb))) -- Keep fraction local to this scope so callbacks do not accidentally overwrite shared globals.
            local target=fraction*range; local negative=list:getShiftY()<0 -- Keep target local to this scope so callbacks do not accidentally overwrite shared globals.
            list:setShiftY(negative and -target or target) -- Adjust list scrolling; zero returns to the start after a changed search or Top action.
            if not negative and target>0 and math.abs(list:getShiftY())<0.001 then list:setShiftY(-target) end -- Adjust list scrolling; zero returns to the start after a changed search or Top action.
        end} -- Close the current function, callback, conditional or loop at this nesting level.
end -- Close the current function, callback, conditional or loop at this nesting level.
local function input(title,text,value,accept,back) -- Open the native text-entry dialog and route Apply/Cancel to explicit callbacks.
    dismiss() -- Close the currently owned dialog/help before constructing the next screen.
    activeDialog=GUI.createRenameDialog{title=title,text=text,value=value or '',okText='Apply', -- Configure the GUI layout/text and callback fields for the surrounding control.
        onOk=function(v) accept(v or '') end,onCancel=back or showMain} -- Define the on Ok callback used by its surrounding screen.
end -- Close the current function, callback, conditional or loop at this nesting level.
local function options(title,values,apply) -- Display a scrollable single-choice list; clicking a row delegates to the supplied apply callback.
    dismiss() -- Close the currently owned dialog/help before constructing the next screen.
    local dialog=GUI.createDialog{title=title,width=400,height=350}; activeDialog=dialog -- Create this screen with an explicit title and bounded dimensions, then retain its owned handle.
    local list=dialog.content:addListBox{width=-22,height=-36} -- Create a scrollable viewport for the current option list or recycled content.
    for _,v in ipairs(values) do local choice=v -- Iterate the indicated entries; ipairs visits ordered rows, while pairs visits ID-keyed maps.
        list:addButton{height=32,text=type(v)=='table' and v.label or v,onClick=function() -- Create an actionable GUI button with the specified placement, label and callback.
            apply(choice) -- Pass the clicked option to the editor callback; that callback owns validation and subsequent navigation.
        end} -- Close the current function, callback, conditional or loop at this nesting level.
    end -- Close the current function, callback, conditional or loop at this nesting level.
    dialog.content:addButton{x=0,y=-30,width=120,height=28,text='Back',onClick=showMain} -- Create an actionable GUI button with the specified placement, label and callback.
    helpButton(dialog.content,{x=-30,y=-30,width=28,height=28},title,'Choose an option to apply it. Other filters still apply, so an empty result may need a wider search. Back returns to the filters. Your shortlist has standards.') -- Provide contextual help using a small square button and the matching topic description.
    scrollbar(dialog.content,'$tenjiku_options_scroll',function() return list end,function() return #values*32 end,0,36) -- Link the visible scrollbar to this list and its full logical content extent.
end -- Close the current function, callback, conditional or loop at this nesting level.
local function form(title,fields,apply,back) -- Build a validated multi-field editor; apply only accepted values and preserve the form on errors.
    dismiss() -- Close the currently owned dialog/help before constructing the next screen.
    local d=GUI.createDialog{title=title,width=400,height=math.min(450,118+#fields*36)}; activeDialog=d -- Create this screen with an explicit title and bounded dimensions, then retain its owned handle.
    local content=d.content; local inputs={} -- Keep content local to this scope so callbacks do not accidentally overwrite shared globals.
    for i,f in ipairs(fields) do -- Iterate the indicated entries; ipairs visits ordered rows, while pairs visits ID-keyed maps.
        local y=(i-1)*36 -- Keep y local to this scope so callbacks do not accidentally overwrite shared globals.
        content:addLabel{x=0,y=y,width=175,height=30,text=f.label} -- Display explanatory text or metadata without changing filter or saved-data state.
        inputs[f.key]=content:addTextField{x=180,y=y,width=-1,height=30,text=f.value==nil and '' or tostring(f.value)} -- Create an editable field; the associated callback validates or applies its text.
    end -- Close the current function, callback, conditional or loop at this nesting level.
    local errorLabel=content:addLabel{x=0,y=#fields*36,width=-1,height=28,text=''} -- Display explanatory text or metadata without changing filter or saved-data state.
    content:addButton{x=0,y=-32,width=125,height=30,text='Apply',onClick=function() -- Create an actionable GUI button with the specified placement, label and callback.
        local values={}; for key,node in pairs(inputs) do values[key]=node:getText() or '' end -- Keep values local to this scope so callbacks do not accidentally overwrite shared globals.
        local ok,message=apply(values) -- Keep ok,message local to this scope so callbacks do not accidentally overwrite shared globals.
        if ok then (back or showMain)() else errorLabel:setText(message or 'Check the values.') end -- Refresh the displayed label to reflect the current binding, choices or result count.
    end} -- Close the current function, callback, conditional or loop at this nesting level.
    content:addButton{x=135,y=-32,width=125,height=30,text='Cancel',onClick=back or showMain} -- Create an actionable GUI button with the specified placement, label and callback.
    helpButton(content,{x=275,y=-32,width=28,height=30},title,title=='Global Theons budget' and helpTopics['Theons budget'] or 'Fill in the labelled fields and Apply. Cancel keeps the previous values. Pack names can use / for subpacks; blank optional numeric limits mean any. No paperwork degree required.') -- Provide contextual help using a small square button and the matching topic description.
end -- Close the current function, callback, conditional or loop at this nesting level.
local function editBudget(back) -- Validate the global price cap; blank or unlimited removes it, while zero remains a valid cap.
    form('Global Theons budget',{{key='cap',label='Maximum (blank = unlimited)',value=db.budgetMax}},function(values) -- Open the labelled form and validate values before saving or navigating back.
        local raw=values.cap:match('^%s*(.-)%s*$') -- Keep raw local to this scope so callbacks do not accidentally overwrite shared globals.
        if raw:lower()=='unlimited' then raw='' end -- Run this branch only when its explicit state, selection or availability condition holds.
        local cap,ok=C.integer(raw,true,true) -- Keep cap,ok local to this scope so callbacks do not accidentally overwrite shared globals.
        if not ok then return false,'Use 0 or a positive whole number, or leave blank for unlimited.' end -- Reject this candidate or invalid value as soon as the stated requirement fails.
        db.budgetMax=cap;persist();return true -- Commit the changed picker data and capture an undo step only if tracked data actually changed.
    end,back or showMain) -- Finish the validation callback and choose the explicit return screen or ordinary filter panel.
end -- Close the current function, callback, conditional or loop at this nesting level.
local function editDimensions(mode) -- Edit inclusive range bounds or plot limits without pretending to inspect actual map tiles.
    local fields -- Keep fields local to this scope so callbacks do not accidentally overwrite shared globals.
    if mode=='Fits within plot' then fields={{key='fitW',label='Plot X / width',value=state.fitW},{key='fitH',label='Plot Y / depth',value=state.fitH}} -- Run this branch only when its explicit state, selection or availability condition holds.
    else fields={{key='minW',label='Minimum X',value=state.minW},{key='maxW',label='Maximum X',value=state.maxW}, -- Apply the fallback branch when the preceding condition did not match.
        {key='minH',label='Minimum Y',value=state.minH},{key='maxH',label='Maximum Y',value=state.maxH}} end -- Describe a field or selectable option with its internal key, visible label and initial value.
    form(mode,fields,function(values) -- Open the labelled form and validate values before saving or navigating back.
        local parsed={}; for key,text in pairs(values) do -- Keep parsed local to this scope so callbacks do not accidentally overwrite shared globals.
            local n,ok=C.integer(text); if not ok then return false,'Use positive whole tile counts.' end; parsed[key]=n -- Keep n,ok local to this scope so callbacks do not accidentally overwrite shared globals.
        end -- Close the current function, callback, conditional or loop at this nesting level.
        if mode=='Size range' and (parsed.minW>parsed.maxW or parsed.minH>parsed.maxH) then return false,'Minimum cannot exceed maximum.' end -- Reject this candidate or invalid value as soon as the stated requirement fails.
        for key,n in pairs(parsed) do state[key]=n end; state.sizeMode=mode; return true -- Iterate the indicated entries; ipairs visits ordered rows, while pairs visits ID-keyed maps.
    end) -- Close the current function, callback, conditional or loop at this nesting level.
end -- Close the current function, callback, conditional or loop at this nesting level.
local function editHeight() -- Edit optional reported visual-height bounds; both blank disables this filter.
    form('Visual height (game units)',{{key='minimum',label='Minimum (blank = any)',value=state.heightMin}, -- Open the labelled form and validate values before saving or navigating back.
        {key='maximum',label='Maximum (blank = any)',value=state.heightMax}},function(values) -- Describe a field or selectable option with its internal key, visible label and initial value.
        local low,a=C.integer(values.minimum,true,true); local high,b=C.integer(values.maximum,true,true) -- Keep low,a local to this scope so callbacks do not accidentally overwrite shared globals.
        if not a or not b then return false,'Use non-negative whole units or leave blank.' end -- Reject this candidate or invalid value as soon as the stated requirement fails.
        if low and high and low>high then return false,'Minimum cannot exceed maximum.' end -- Reject this candidate or invalid value as soon as the stated requirement fails.
        state.heightMin,state.heightMax=low,high; return true -- Apply the accepted optional height bounds together and signal successful form validation.
    end) -- Close the current function, callback, conditional or loop at this nesting level.
end -- Close the current function, callback, conditional or loop at this nesting level.
local function multi(title,values,inc,exc,back,selectionCaption) -- Build searchable include/exclude or membership controls with mode-specific empty-state semantics.
    local mode=selectionCaption=='pack memberships' and 'memberships' or selectionCaption=='packs to browse' and 'browse' or title:find('Exact footprints',1,true) and 'sizes' or title:find('wealth',1,true) and 'wealth' or title=='Installed plugin packs' and 'sources' or 'types' -- Keep mode local to this scope so callbacks do not accidentally overwrite shared globals.
    local allowExclude=exc~=nil -- Keep allow Exclude local to this scope so callbacks do not accidentally overwrite shared globals.
    exc=exc or {} -- Update exc for the current operation; subsequent controls/filters read this state.
    dismiss() -- Close the currently owned dialog/help before constructing the next screen.
    local d=GUI.createDialog{title=title,width=520,height=430}; activeDialog=d -- Create this screen with an explicit title and bounded dimensions, then retain its owned handle.
    local p=d.content; local list=nil; local extent=0; local old=nil; local rebuild -- Keep p local to this scope so callbacks do not accidentally overwrite shared globals.
    p:addLabel{x=0,y=0,width=48,height=30,text='Search'} -- Display explanatory text or metadata without changing filter or saved-data state.
    local search=p:addTextField{x=50,y=0,width=-104,height=30,text='',onUpdate=function(self) -- Create an editable field; the associated callback validates or applies its text.
        local text=self:getText() or ''; if rebuild and text~=old then rebuild(text) end -- Keep text local to this scope so callbacks do not accidentally overwrite shared globals.
    end} -- Close the current function, callback, conditional or loop at this nesting level.
    local summary=p:addLabel{x=0,y=34,width=-34,height=24,text=''} -- Display explanatory text or metadata without changing filter or saved-data state.
    local searchCount=p:addLabel{x=0,y=58,width=-1,height=24,text=''} -- Display explanatory text or metadata without changing filter or saved-data state.
    helpButton(p,{x=-30,y=34,width=28,height=24},title,allowExclude and 'Include several choices to combine them. Empty includes allows all; Exclude vetoes a choice. Search only narrows this list, not your saved choices. Done applies them. Be picky; it is your skyline.' or (selectionCaption=='pack memberships' and 'Include means this building belongs to that personal pack. Toggle again to remove membership; Done saves. One building can join several packs. A very social skyscraper.' or 'Toggle Include for the choices you want, then Done. Search hides rows without clearing choices. The count tracks choices, not newly created packs. Your shortlist, your rules.')) -- Provide contextual help using a small square button and the matching topic description.
    rebuild=function(query) -- Define the rebuild callback used by its surrounding screen.
        old=query; if list then list:delete() end -- Dispose the previous owned list/control before replacing it, avoiding stacked stale GUI trees.
        list=p:addListBox{id='$tenjiku_multi_results',x=0,y=86,width=-22,height=-42} -- Create a scrollable viewport for the current option list or recycled content.
        local count=0 -- Keep count local to this scope so callbacks do not accidentally overwrite shared globals.
        for _,v in ipairs(values) do local value=v -- Iterate the indicated entries; ipairs visits ordered rows, while pairs visits ID-keyed maps.
            if query=='' or string.find(value.label:lower(),query:lower(),1,true) then -- Run this branch only when its explicit state, selection or availability condition holds.
                count=count+1 -- Update count for the current operation; subsequent controls/filters read this state.
                local row=list:addCanvas{height=42} -- Create a layout/content container; its logical dimensions can exceed the visible viewport.
                row:addLabel{x=2,y=0,width=-155,height=40,text=value.label} -- Display explanatory text or metadata without changing filter or saved-data state.
                row:addButton{x=allowExclude and -150 or -75,y=5,width=72,height=30,text='Include',isPressed=function() return inc[value.key]==true end, -- Create an actionable GUI button with the specified placement, label and callback.
                    onClick=function() inc[value.key]=not inc[value.key] or nil; if inc[value.key] then exc[value.key]=nil end; rebuild(old) end} -- Define the on Click callback used by its surrounding screen.
                if allowExclude then row:addButton{x=-75,y=5,width=72,height=30,text='Exclude',isPressed=function() return exc[value.key]==true end, -- Create an actionable GUI button with the specified placement, label and callback.
                    onClick=function() exc[value.key]=not exc[value.key] or nil; if exc[value.key] then inc[value.key]=nil end; rebuild(old) end} end -- Define the on Click callback used by its surrounding screen.
            end -- Close the current function, callback, conditional or loop at this nesting level.
        end -- Close the current function, callback, conditional or loop at this nesting level.
        summary:setText(C.choiceSummary(inc,exc,mode)) -- Refresh the displayed label to reflect the current binding, choices or result count.
        local noun=mode=='sources' and 'source entries' or mode=='types' and 'building types' or mode=='sizes' and 'footprints' or mode=='wealth' and 'wealth levels' or 'personal packs' -- Keep noun local to this scope so callbacks do not accidentally overwrite shared globals.
        searchCount:setText(count..' of '..#values..' '..noun..' match list search') -- Refresh the displayed label to reflect the current binding, choices or result count.
        extent=math.max(52,count*42) -- Update extent for the current operation; subsequent controls/filters read this state.
        if count==0 then list:addLabel{height=52,text='No list entries match this search. Your filter choices stay unchanged.'} end -- Display explanatory text or metadata without changing filter or saved-data state.
    end -- Close the current function, callback, conditional or loop at this nesting level.
    p:addButton{x=-96,y=0,width=96,height=30,text='Clear search',onClick=function() search:setText(''); rebuild('') end} -- Create an actionable GUI button with the specified placement, label and callback.
    p:addButton{x=0,y=-34,width=120,height=30,text='Done',onClick=back or showMain} -- Create an actionable GUI button with the specified placement, label and callback.
    p:addButton{x=128,y=-34,width=140,height=30,text=mode=='memberships' and 'Remove from all' or ((mode=='browse' or mode=='sizes') and 'Select none' or 'Allow all'),onClick=function() -- Create an actionable GUI button with the specified placement, label and callback.
        for key in pairs(inc) do inc[key]=nil end; for key in pairs(exc) do exc[key]=nil end; rebuild(old) -- Iterate the indicated entries; ipairs visits ordered rows, while pairs visits ID-keyed maps.
    end} -- Close the current function, callback, conditional or loop at this nesting level.
    scrollbar(p,'$tenjiku_multi_scroll',function() return list end,function() return extent end,86,42) -- Link the visible scrollbar to this list and its full logical content extent.
    rebuild('') -- Refresh the list/search presentation using existing working state and reusable row bindings.
end -- Close the current function, callback, conditional or loop at this nesting level.
local function editExact() -- Offer discovered and already-selected footprints; no chosen exact footprints deliberately matches nothing.
    local values,seen={},{} -- Keep values,seen local to this scope so callbacks do not accidentally overwrite shared globals.
    for _,item in ipairs(catalog or {}) do -- Iterate the indicated entries; ipairs visits ordered rows, while pairs visits ID-keyed maps.
        local key=item.w..'x'..item.h -- Keep key local to this scope so callbacks do not accidentally overwrite shared globals.
        if not seen[key] then seen[key]=true; values[#values+1]={key=key,label=key} end -- Run this branch only when its explicit state, selection or availability condition holds.
    end -- Close the current function, callback, conditional or loop at this nesting level.
    for key in pairs(state.sizes) do if not seen[key] then values[#values+1]={key=key,label=key} end end -- Iterate the indicated entries; ipairs visits ordered rows, while pairs visits ID-keyed maps.
    table.sort(values,function(a,b) return a.label<b.label end) -- Order this array with the supplied comparator without modifying original building definitions.
    -- Size selection uses Include toggles; an empty set deliberately matches nothing.
    multi('Exact footprints (select several)',values,state.sizes,nil,function() state.sizeMode='Exact sizes'; showMain() end) -- Open a searchable multi-choice list with the supplied include, exclude or membership sets.
end -- Close the current function, callback, conditional or loop at this nesting level.
local function sizeMenu() -- Route the selected footprint mode to its matching editor or immediately apply Any size.
    options('Size filter',{'Exact sizes','Enter several sizes','Size range','Fits within plot','Any size'},function(value) -- Open a single-choice editor and apply only the option the player clicks.
        if value=='Exact sizes' then editExact() -- Run this branch only when its explicit state, selection or availability condition holds.
        elseif value=='Enter several sizes' then -- Handle the next mutually exclusive case when preceding conditions did not apply.
            local selected={}; for key,enabled in pairs(state.sizes) do if enabled then selected[#selected+1]=key end end; table.sort(selected) -- Keep selected local to this scope so callbacks do not accidentally overwrite shared globals.
            input('Enter footprints','Example: 1x1, 2x2, 2x3. Separate sizes with commas.',table.concat(selected,', '),function(text) -- Request a text value and route accepted or cancelled input to the correct screen.
                local set,err=C.parseSizes(text) -- Keep set,err local to this scope so callbacks do not accidentally overwrite shared globals.
                if not set then Debug.toast(err); sizeMenu(); return end -- Explain the result or validation issue through a short in-game message.
                state.sizes=set; state.sizeMode='Exact sizes'; showMain() -- Update state.sizes for the current operation; subsequent controls/filters read this state.
            end,sizeMenu) -- On cancelling manual footprint input, return to the size-mode chooser.
        elseif value=='Size range' or value=='Fits within plot' then editDimensions(value) -- Handle the next mutually exclusive case when preceding conditions did not apply.
        else state.sizeMode='Any size'; showMain() end -- Apply the fallback branch when the preceding condition did not match.
    end) -- Close the current function, callback, conditional or loop at this nesting level.
end -- Close the current function, callback, conditional or loop at this nesting level.
local function selectPlacement(item) -- Defer native placement until the dialog closes, then recheck city epoch and current definition.
    local captured=epoch -- Keep captured local to this scope so callbacks do not accidentally overwrite shared globals.
    dismiss() -- Close the currently owned dialog/help before constructing the next screen.
    Runtime.postpone(function() -- Queue the placement handoff until the current dialog has closed; later checks guard city changes.
        if not inCity or captured~=epoch then return end -- Handle a guard/terminal case immediately instead of continuing with unsuitable state.
        scan() -- Rebuild current loaded definitions and clear obsolete active source/type restrictions.
        item=byId[item.id] -- Update item for the current operation; subsequent controls/filters read this state.
        if not item then Debug.toast('This building is no longer loaded. Reopen the picker for updated listings.');return end -- Explain the result or validation issue through a short in-game message.
        local d=drawer(item) -- Keep d local to this scope so callbacks do not accidentally overwrite shared globals.
        if not d then Debug.toast('This building has no available placement tool.'); return end -- Explain the result or validation issue through a short in-game message.
        local ok,can=pcall(d.isSelectable) -- Protect the native/API operation so a failed method can be handled without aborting the tool.
        if not ok or not can then -- Run this branch only when its explicit state, selection or availability condition holds.
            activeDialog=GUI.createDialog{title='Building unavailable',width=380,height=160, -- Create this screen with an explicit title and bounded dimensions, then retain its owned handle.
                text='TheoTown currently disallows this building. Check unlocks, manual-building availability, game mode and funds.'} -- Update text for the current operation; subsequent controls/filters read this state.
            return -- Stop this callback now; the required handoff or feedback has already been handled.
        end -- Close the current function, callback, conditional or loop at this nesting level.
        local success,err=pcall(d.select) -- Protect the native/API operation so a failed method can be handled without aborting the tool.
        if success then C.record(db,item.id); persist() -- Commit the changed picker data and capture an undo step only if tracked data actually changed.
        else Debug.toast('Could not open placement: '..tostring(err)) end -- Apply the fallback branch when the preceding condition did not match.
    end) -- Close the current function, callback, conditional or loop at this nesting level.
end -- Close the current function, callback, conditional or loop at this nesting level.
local function money(value) return value==nil and 'Price unknown' or tostring(value)..' Theons' end -- Label unknown base prices explicitly and format known values in Theons.
local function wealthLabel(item) -- Translate RCI levels 0/1/2 into T/TT/TTT; identify non-RCI definitions separately.
    return item.rci and ({[0]='T',[1]='TT',[2]='TTT'})[item.level] or 'Not RCI' -- Return the computed value or finish this branch immediately, leaving callers to handle the result.
end -- Close the current function, callback, conditional or loop at this nesting level.
local function sizeLabel() -- Summarise the active footprint rule, including the intentionally empty exact-size state.
    if state.sizeMode=='Any size' then return 'Any size' end -- Handle a guard/terminal case immediately instead of continuing with unsuitable state.
    if state.sizeMode=='Exact sizes' then -- Run this branch only when its explicit state, selection or availability condition holds.
        local keys={}; for key,v in pairs(state.sizes) do if v then keys[#keys+1]=key end end; table.sort(keys) -- Keep keys local to this scope so callbacks do not accidentally overwrite shared globals.
        return #keys==0 and 'None chosen - no matches' or (#keys==1 and keys[1] or (#keys..' chosen footprints')) -- Return the computed value or finish this branch immediately, leaving callers to handle the result.
    end -- Close the current function, callback, conditional or loop at this nesting level.
    if state.sizeMode=='Fits within plot' then return 'Fits '..state.fitW..'x'..state.fitH end -- Handle a guard/terminal case immediately instead of continuing with unsuitable state.
    return state.minW..'-'..state.maxW..' x '..state.minH..'-'..state.maxH -- Return the computed value or finish this branch immediately, leaving callers to handle the result.
end -- Close the current function, callback, conditional or loop at this nesting level.

local function categoryValues() -- List personal-pack names with deduplicated loaded-member counts for selection screens.
    local values={} -- Keep values local to this scope so callbacks do not accidentally overwrite shared globals.
    for name in pairs(db.categories) do -- Iterate the indicated entries; ipairs visits ordered rows, while pairs visits ID-keyed maps.
        values[#values+1]={key=name,label=name:gsub('/', ' / ')..' ('..C.categoryCount(db,name,byId)..' loaded buildings)'} -- Add one named personal pack and its deduplicated currently loaded subtree-member count.
    end -- Close the current function, callback, conditional or loop at this nesting level.
    table.sort(values,function(a,b) return a.key:lower()<b.key:lower() end) -- Order this array with the supplied comparator without modifying original building definitions.
    return values -- Return the computed value or finish this branch immediately, leaving callers to handle the result.
end -- Close the current function, callback, conditional or loop at this nesting level.
local function createCategory(back,cancel) -- Validate a new pack name and description, persist it and return to the requested screen.
    local created=nil -- Keep created local to this scope so callbacks do not accidentally overwrite shared globals.
    form('Create personal building pack',{ -- Open the labelled form and validate values before saving or navigating back.
        {key='name',label='Pack name',value=''}, -- Describe a field or selectable option with its internal key, visible label and initial value.
        {key='description',label='Short description',value=''} -- Describe a field or selectable option with its internal key, visible label and initial value.
    },function(values) -- Finish the field specification and begin validating the submitted form-value map.
        local name,err=C.categoryPath(values.name) -- Keep name,err local to this scope so callbacks do not accidentally overwrite shared globals.
        if not name then return false,err end -- Reject this candidate or invalid value as soon as the stated requirement fails.
        if db.categories[name] then return false,'That pack name already exists.' end -- Reject this candidate or invalid value as soon as the stated requirement fails.
        if #values.description>300 then return false,'Keep the description within 300 characters.' end -- Reject this candidate or invalid value as soon as the stated requirement fails.
        C.ensureCategory(db,name); db.packDescriptions[name]=values.description -- Delegate this operation to the pure data helper so UI actions share the same validated behaviour.
        persist(); created=name; return true -- Commit the changed picker data and capture an undo step only if tracked data actually changed.
    end,function() -- Finish validation and begin the success/cancel return callback for the enclosing editor.
        if created then if back then back() else categoryEditor(created) end else (cancel or categoryManager)() end -- Run this branch only when its explicit state, selection or availability condition holds.
    end) -- Close the current function, callback, conditional or loop at this nesting level.
end -- Close the current function, callback, conditional or loop at this nesting level.
assignCategories=function(item,back) -- Edit one building's direct memberships across personal packs and save them on Done.
    if not next(db.categories) then createCategory(function() assignCategories(item,back) end,back or browse); return end -- Handle a guard/terminal case immediately instead of continuing with unsuitable state.
    local selected={} -- Keep selected local to this scope so callbacks do not accidentally overwrite shared globals.
    for name,members in pairs(db.categories) do if members[item.id] then selected[name]=true end end -- Iterate the indicated entries; ipairs visits ordered rows, while pairs visits ID-keyed maps.
    multi('Assign packs: '..item.title,categoryValues(),selected,nil,function() -- Open a searchable multi-choice list with the supplied include, exclude or membership sets.
        for name in pairs(db.categories) do C.setPackMember(db,name,item.id,selected[name]) end -- Iterate the indicated entries; ipairs visits ordered rows, while pairs visits ID-keyed maps.
        persist(); (back or browse)() -- Commit the changed picker data and capture an undo step only if tracked data actually changed.
    end,'pack memberships') -- Set membership-specific summaries so an empty choice means unassigned rather than unrestricted filtering.
end -- Close the current function, callback, conditional or loop at this nesting level.
local function finishPackEdit() -- Leave membership-edit mode, restore the previous kit filters and return to the edited pack.
    local name=editingPack -- Keep name local to this scope so callbacks do not accidentally overwrite shared globals.
    editingPack=nil -- Update editing Pack for the current operation; subsequent controls/filters read this state.
    if editingReturnState then state=editingReturnState end -- Run this branch only when its explicit state, selection or availability condition holds.
    editingReturnState=nil -- Update editing Return State for the current operation; subsequent controls/filters read this state.
    persist() -- Commit the changed picker data and capture an undo step only if tracked data actually changed.
    if name and db.categories[name] then categoryEditor(name) else categoryManager() end -- Run this branch only when its explicit state, selection or availability condition holds.
end -- Close the current function, callback, conditional or loop at this nesting level.
local function startPackEdit(name) -- Start a clean Any-size candidate search while retaining the previous kit filter state.
    advancedOpen=false -- Update advanced Open for the current operation; subsequent controls/filters read this state.
    if not editingPack then editingReturnState=C.copy(state) end -- Run this branch only when its explicit state, selection or availability condition holds.
    editingPack=name -- Update editing Pack for the current operation; subsequent controls/filters read this state.
    state=C.defaults(); state.sizeMode='Any size' -- Update state for the current operation; subsequent controls/filters read this state.
    showMain() -- Render the current mode's filter panel using its active working state.
end -- Close the current function, callback, conditional or loop at this nesting level.
categoryEditor=function(name) -- Display pack browsing, membership, bulk addition, rename/description and deletion actions.
    if not db.categories[name] then categoryManager(); return end -- Handle a guard/terminal case immediately instead of continuing with unsuitable state.
    dismiss() -- Close the currently owned dialog/help before constructing the next screen.
    local d=GUI.createDialog{title=name:gsub('/', ' / '),width=520,height=450}; activeDialog=d -- Create this screen with an explicit title and bounded dimensions, then retain its owned handle.
    local p=d.content -- Keep p local to this scope so callbacks do not accidentally overwrite shared globals.
    local members=C.categoryCount(db,name,byId) -- Keep members local to this scope so callbacks do not accidentally overwrite shared globals.
    p:addTextFrame{x=0,y=0,width=-1,height=78, -- Display explanatory text or metadata without changing filter or saved-data state.
        text=(db.packDescriptions[name] or '')..'\n'..members..' loaded buildings | Missing plugins are hidden; subpacks included.'} -- Update text for the current operation; subsequent controls/filters read this state.
    local list=p:addListBox{x=0,y=86,width=-22,height=-40} -- Create a scrollable viewport for the current option list or recycled content.
    local function row(label,action) -- Create one compact action row and, where supplied, its adjacent contextual-help button.
        local line=list:addCanvas{height=34} -- Create a layout/content container; its logical dimensions can exceed the visible viewport.
        line:addButton{width=-34,height=32,text=label,onClick=action} -- Create an actionable GUI button with the specified placement, label and callback.
        local title,message=helpFor(label) -- Keep title,message local to this scope so callbacks do not accidentally overwrite shared globals.
        helpButton(line,{x=-30,y=0,width=28,height=32},title,message) -- Provide contextual help using a small square button and the matching topic description.
    end -- Close the current function, callback, conditional or loop at this nesting level.
    row('Browse all buildings in pack',function() -- Add this named control to the current screen and wire it to its dedicated editor/action.
        editingPack=nil;editingReturnState=nil -- Update editing Pack for the current operation; subsequent controls/filters read this state.
        state=C.defaults(); state.sizeMode='Any size'; state.customCategories={[name]=true}; browse() -- Update state for the current operation; subsequent controls/filters read this state.
    end) -- Close the current function, callback, conditional or loop at this nesting level.
    row('Browse pack by building type',function() -- Add this named control to the current screen and wire it to its dedicated editor/action.
        local counts={} -- Keep counts local to this scope so callbacks do not accidentally overwrite shared globals.
        for _,item in ipairs(catalog or {}) do -- Iterate the indicated entries; ipairs visits ordered rows, while pairs visits ID-keyed maps.
            if C.inCategory(db,name,item.id) then counts[item.kind]=(counts[item.kind] or 0)+1 end -- Run this branch only when its explicit state, selection or availability condition holds.
        end -- Close the current function, callback, conditional or loop at this nesting level.
        local choices={};for kind,n in pairs(counts) do choices[#choices+1]={key=kind,label=kind..' ('..n..')'} end -- Keep choices local to this scope so callbacks do not accidentally overwrite shared globals.
        table.sort(choices,function(a,b) return a.key<b.key end) -- Order this array with the supplied comparator without modifying original building definitions.
        if #choices==0 then Debug.toast('Add some buildings to this pack first.'); return end -- Explain the result or validation issue through a short in-game message.
        options('Types in '..name,choices,function(v) -- Open a single-choice editor and apply only the option the player clicks.
            editingPack=nil;editingReturnState=nil -- Update editing Pack for the current operation; subsequent controls/filters read this state.
            state=C.defaults(); state.sizeMode='Any size'; state.customCategories={[name]=true}; state.typesIn={[v.key]=true}; browse() -- Update state for the current operation; subsequent controls/filters read this state.
        end) -- Close the current function, callback, conditional or loop at this nesting level.
    end) -- Close the current function, callback, conditional or loop at this nesting level.
    row('Add / remove buildings (with filters)',function() startPackEdit(name) end) -- Add this named control to the current screen and wire it to its dedicated editor/action.
    row('Add all current filtered matches',function() -- Add this named control to the current screen and wire it to its dedicated editor/action.
        local added=C.addToPack(db,name,getResults(false));persist() -- Commit the changed picker data and capture an undo step only if tracked data actually changed.
        Debug.toast('Added '..added..' new buildings.');categoryEditor(name) -- Explain the result or validation issue through a short in-game message.
    end) -- Close the current function, callback, conditional or loop at this nesting level.
    row('Edit pack name / description',function() -- Add this named control to the current screen and wire it to its dedicated editor/action.
        local target=name -- Keep target local to this scope so callbacks do not accidentally overwrite shared globals.
        form('Edit personal building pack',{ -- Open the labelled form and validate values before saving or navigating back.
            {key='name',label='Pack name / folder',value=name}, -- Describe a field or selectable option with its internal key, visible label and initial value.
            {key='description',label='Short description',value=db.packDescriptions[name] or ''} -- Describe a field or selectable option with its internal key, visible label and initial value.
        },function(values) -- Finish the field specification and begin validating the submitted form-value map.
            local new,err=C.categoryPath(values.name) -- Keep new,err local to this scope so callbacks do not accidentally overwrite shared globals.
            if not new then return false,err end -- Reject this candidate or invalid value as soon as the stated requirement fails.
            if #values.description>300 then return false,'Keep the description within 300 characters.' end -- Reject this candidate or invalid value as soon as the stated requirement fails.
            local ok,message,mapping=C.renameCategory(db,name,new,state) -- Keep ok,message,mapping local to this scope so callbacks do not accidentally overwrite shared globals.
            if not ok then return false,message end -- Reject this candidate or invalid value as soon as the stated requirement fails.
            if mapping then -- Run this branch only when its explicit state, selection or availability condition holds.
                updateCategoryFilters(editingReturnState,mapping) -- Keep the kit state that will be restored after membership editing consistent with renamed pack paths.
                if editingPack and mapping[editingPack] then editingPack=mapping[editingPack] end -- Run this branch only when its explicit state, selection or availability condition holds.
            end -- Close the current function, callback, conditional or loop at this nesting level.
            target=new;db.packDescriptions[new]=values.description;persist();return true -- Commit the changed picker data and capture an undo step only if tracked data actually changed.
        end,function() categoryEditor(target) end) -- After completing or cancelling the form, reopen the correct current pack path.
    end) -- Close the current function, callback, conditional or loop at this nesting level.
    row('Delete pack and subpacks',function() -- Add this named control to the current screen and wire it to its dedicated editor/action.
        dismiss() -- Close the currently owned dialog/help before constructing the next screen.
        activeDialog=GUI.createDialog{title='Delete personal pack?',width=420,height=180, -- Create this screen with an explicit title and bounded dimensions, then retain its owned handle.
            text='Remove '..name..' and its subpacks? Installed buildings and other packs remain.', -- Update text for the current operation; subsequent controls/filters read this state.
            actions={{text='Cancel',onClick=function() categoryEditor(name) end}, -- Handle this button click using its supplied closure; capture the current item/state before acting.
                {text='Delete',onClick=function() -- Handle this button click using its supplied closure; capture the current item/state before acting.
                    C.deleteCategory(db,name,state) -- Delegate this operation to the pure data helper so UI actions share the same validated behaviour.
                    if editingPack and (editingPack==name or editingPack:sub(1,#name+1)==name..'/') then -- Run this branch only when its explicit state, selection or availability condition holds.
                        editingPack=nil;editingReturnState=nil -- Update editing Pack for the current operation; subsequent controls/filters read this state.
                    end -- Close the current function, callback, conditional or loop at this nesting level.
                    persist();categoryManager() -- Commit the changed picker data and capture an undo step only if tracked data actually changed.
                end}}} -- Finish the deletion callback, confirmation actions array and confirmation-dialog specification.
    end) -- Close the current function, callback, conditional or loop at this nesting level.
    p:addButton{x=0,y=-32,width=150,height=30,text='Back to packs',onClick=categoryManager} -- Create an actionable GUI button with the specified placement, label and callback.
    historyButtons(p,-32,function() categoryEditor(name) end,160) -- Expose the shared ten-step picker-data history and its scope explanation on this screen.
    scrollbar(p,'$tenjiku_pack_editor_scroll',function() return list end,function() return 6*34 end,86,40) -- Link the visible scrollbar to this list and its full logical content extent.
end -- Close the current function, callback, conditional or loop at this nesting level.

categoryManager=function() -- Display searchable personal packs and distinguish Browse from Edit without mixing normal-mode controls.
    if currentMode~='kit' then -- Run this branch only when its explicit state, selection or availability condition holds.
        normalState=state;state=kitState;currentMode='kit' -- Update normal State for the current operation; subsequent controls/filters read this state.
    end -- Close the current function, callback, conditional or loop at this nesting level.
    if not catalog then scan() end -- Run this branch only when its explicit state, selection or availability condition holds.
    dismiss() -- Close the currently owned dialog/help before constructing the next screen.
    local d=GUI.createDialog{title='Pack Building Kit - Your packs',width=580,height=460}; activeDialog=d -- Create this screen with an explicit title and bounded dimensions, then retain its owned handle.
    local p=d.content; local list=nil; local extent=0; local previous=nil; local rebuild -- Keep p local to this scope so callbacks do not accidentally overwrite shared globals.
    p:addLabel{x=0,y=0,width=48,height=30,text='Search'} -- Display explanatory text or metadata without changing filter or saved-data state.
    local search=p:addTextField{id='$tenjiku_category_search',x=50,y=0,width=-104,height=30,text='',onUpdate=function(self) -- Create an editable field; the associated callback validates or applies its text.
        local text=self:getText() or ''; if rebuild and text~=previous then rebuild(text) end -- Keep text local to this scope so callbacks do not accidentally overwrite shared globals.
    end} -- Close the current function, callback, conditional or loop at this nesting level.
    local summary=p:addLabel{x=0,y=34,width=-1,height=24,text=''} -- Display explanatory text or metadata without changing filter or saved-data state.
    p:addButton{x=0,y=62,width=125,height=30,text='New pack',onClick=function() createCategory() end} -- Create an actionable GUI button with the specified placement, label and callback.
    p:addButton{x=133,y=62,width=160,height=30,text='Browse several packs',onClick=function() -- Create an actionable GUI button with the specified placement, label and callback.
        local chosen=C.copy(state.customCategories) -- Keep chosen local to this scope so callbacks do not accidentally overwrite shared globals.
        multi('Choose packs to browse',categoryValues(),chosen,nil,function() -- Open a searchable multi-choice list with the supplied include, exclude or membership sets.
            if not C.any(chosen) then Debug.toast('Choose at least one pack to browse.');categoryManager();return end -- Explain the result or validation issue through a short in-game message.
            state=C.defaults();state.sizeMode='Any size';state.customCategories=chosen;browse() -- Update state for the current operation; subsequent controls/filters read this state.
        end,'packs to browse') -- Use pack-browsing summaries that explicitly require at least one chosen personal pack.
    end} -- Close the current function, callback, conditional or loop at this nesting level.
    
    rebuild=function(query) -- Define the rebuild callback used by its surrounding screen.
        previous=query; if list then list:delete() end -- Dispose the previous owned list/control before replacing it, avoiding stacked stale GUI trees.
        list=p:addListBox{id='$tenjiku_category_results',x=0,y=100,width=-22,height=-42} -- Create a scrollable viewport for the current option list or recycled content.
        local count=0 -- Keep count local to this scope so callbacks do not accidentally overwrite shared globals.
        for _,value in ipairs(categoryValues()) do local entry=value -- Iterate the indicated entries; ipairs visits ordered rows, while pairs visits ID-keyed maps.
            if query=='' or entry.key:lower():find(query:lower(),1,true) then -- Run this branch only when its explicit state, selection or availability condition holds.
                count=count+1 -- Update count for the current operation; subsequent controls/filters read this state.
                local row=list:addCanvas{height=66} -- Create a layout/content container; its logical dimensions can exceed the visible viewport.
                row:addLabel{x=2,y=2,width=-150,height=30,text=entry.label} -- Display explanatory text or metadata without changing filter or saved-data state.
                row:addLabel{x=2,y=34,width=-150,height=28,text=db.packDescriptions[entry.key] or ''} -- Display explanatory text or metadata without changing filter or saved-data state.
                row:addButton{x=-146,y=8,width=68,height=30,text='Browse',onClick=function() -- Create an actionable GUI button with the specified placement, label and callback.
                    editingPack=nil;editingReturnState=nil -- Update editing Pack for the current operation; subsequent controls/filters read this state.
                    state=C.defaults(); state.sizeMode='Any size'; state.customCategories={[entry.key]=true}; browse() -- Update state for the current operation; subsequent controls/filters read this state.
                end} -- Close the current function, callback, conditional or loop at this nesting level.
                row:addButton{x=-74,y=8,width=70,height=30,text='Edit',onClick=function() categoryEditor(entry.key) end} -- Create an actionable GUI button with the specified placement, label and callback.
            end -- Close the current function, callback, conditional or loop at this nesting level.
        end -- Close the current function, callback, conditional or loop at this nesting level.
        summary:setText(count..' of '..C.count(db.categories)..' personal packs/folders match search') -- Refresh the displayed label to reflect the current binding, choices or result count.
        extent=math.max(70,count*66) -- Update extent for the current operation; subsequent controls/filters read this state.
        if count==0 then list:addLabel{height=70,text=C.any(db.categories) and 'No pack names match this search. Clear the search to see your packs.' or 'No personal packs yet. Click New pack to create one.'} end -- Display explanatory text or metadata without changing filter or saved-data state.
    end -- Close the current function, callback, conditional or loop at this nesting level.
    p:addButton{x=-96,y=0,width=96,height=30,text='Clear search',onClick=function() search:setText(''); rebuild('') end} -- Create an actionable GUI button with the specified placement, label and callback.
    helpButton(p,{x=-30,y=-34,width=28,height=30},'Your personal packs','New pack creates a named collection. Edit manages its members; Browse places them. Browse several combines chosen packs. Saved counts stored collections, not an active filter. Packs reference installed buildings, so keep the originals installed. Missing plugins disappear from listings and counts. Personal pack names stay editable, even if empty. Saved memberships return if originals are reinstalled. Your district mixtape.') -- Provide contextual help using a small square button and the matching topic description.
    p:addButton{x=0,y=-34,width=140,height=30,text='Home',onClick=showHome} -- Create an actionable GUI button with the specified placement, label and callback.
    historyButtons(p,-34,categoryManager,150) -- Expose the shared ten-step picker-data history and its scope explanation on this screen.
    scrollbar(p,'$tenjiku_category_scroll',function() return list end,function() return extent end,100,42) -- Link the visible scrollbar to this list and its full logical content extent.
    rebuild('') -- Refresh the list/search presentation using existing working state and reusable row bindings.
end -- Close the current function, callback, conditional or loop at this nesting level.


browse=function() -- Rescan definitions and display the full filtered catalogue using twelve reusable result rows.
    scan() -- Rebuild current loaded definitions and clear obsolete active source/type restrictions.
    local base=getResults(true) -- Keep base local to this scope so callbacks do not accidentally overwrite shared globals.
    dismiss() -- Close the currently owned dialog/help before constructing the next screen.
    local d=GUI.createDialog{title=editingPack and ('Choose buildings: '..editingPack) or ('Buildings: '..sizeLabel()),width=630,height=490} -- Create this screen with an explicit title and bounded dimensions, then retain its owned handle.
    activeDialog=d -- Update active Dialog for the current operation; subsequent controls/filters read this state.
    local p=d.content -- Keep p local to this scope so callbacks do not accidentally overwrite shared globals.
    helpButton(p,{x=-30,y=34,width=28,height=24},'Building results','Search narrows these results; scroll for more. Build starts normal placement. Fav saves a favourite; Hide hides it from this picker. In the kit, Packs edits memberships and Add/Remove updates your current pack immediately. Random favourite picks an available favourite matching your filters. Bulk actions affect ALL matches. No zoning magic, just excellent taste.') -- Provide contextual help using a small square button and the matching topic description.
    local rowHeight=88 -- Logical height of each building result; scrolling divides by this to find the first visible index.
    local poolSize=12 -- Bound the number of building rows independently of catalogue size.
    local matches={} -- Keep matches local to this scope so callbacks do not accidentally overwrite shared globals.
    local extent=52 -- Keep extent local to this scope so callbacks do not accidentally overwrite shared globals.
    local previous=nil -- Keep previous local to this scope so callbacks do not accidentally overwrite shared globals.
    local updateRows,rebuild -- Keep update Rows,rebuild local to this scope so callbacks do not accidentally overwrite shared globals.
    p:addLabel{x=0,y=0,width=48,height=30,text='Search'} -- Display explanatory text or metadata without changing filter or saved-data state.
    local search=p:addTextField{id='$tenjiku_picker_search',x=50,y=0,width=-104,height=30,text=state.query, -- Create an editable field; the associated callback validates or applies its text.
        onUpdate=function(self) -- Define the on Update callback used by its surrounding screen.
            local text=self:getText() or '' -- Keep text local to this scope so callbacks do not accidentally overwrite shared globals.
            if rebuild and text~=previous then rebuild(text) end -- Run this branch only when its explicit state, selection or availability condition holds.
        end} -- Close the current function, callback, conditional or loop at this nesting level.
    local count=p:addLabel{x=0,y=34,width=-1,height=24,text=''} -- Display explanatory text or metadata without changing filter or saved-data state.
    local list=p:addListBox{id='$tenjiku_picker_results',x=0,y=62,width=-22,height=-76, -- Create a scrollable viewport for the current option list or recycled content.
        onUpdate=function() if updateRows then updateRows() end end} -- Define the on Update callback used by its surrounding screen.
    -- Only one content spacer plus a fixed row pool, independent of catalogue size.
    local content=list:addCanvas{id='$tenjiku_virtual_rows',x=0,y=0,height=52} -- Create a layout/content container; its logical dimensions can exceed the visible viewport.
    local empty=content:addLabel{x=0,y=0,width=-1,height=52,text='No buildings match. Clear search or adjust filters, budget and hidden-item settings.'} -- Display explanatory text or metadata without changing filter or saved-data state.
    local slots={} -- Store reusable row controls rather than allocating a new GUI tree for each logical result.
    local function reload() browse() end -- Reopen the result browser after a saved mark or membership assignment changes.
    local function safeItem(slot) return slot.item end -- Read the row's currently bound metadata so recycled controls never target its previous building.
    for i=1,poolSize do -- Iterate the indicated entries; ipairs visits ordered rows, while pairs visits ID-keyed maps.
        local slot={item=nil,index=nil} -- Keep slot local to this scope so callbacks do not accidentally overwrite shared globals.
        slot.row=content:addCanvas{x=0,y=(i-1)*rowHeight,width=-1,height=rowHeight} -- Create a layout/content container; its logical dimensions can exceed the visible viewport.
        slot.icon=slot.row:addIcon{x=2,y=2,width=76,height=82} -- Create a lightweight thumbnail slot; binding supplies a static atlas frame when available.
        slot.title=slot.row:addLabel{x=84,y=2,width=-145,height=29,text=''} -- Display explanatory text or metadata without changing filter or saved-data state.
        slot.info=slot.row:addLabel{x=84,y=31,width=-145,height=25,text=''} -- Display explanatory text or metadata without changing filter or saved-data state.
        slot.source=slot.row:addLabel{x=84,y=57,width=-145,height=24,text=''} -- Display explanatory text or metadata without changing filter or saved-data state.
        slot.action=slot.row:addButton{x=-68,y=4,width=64,height=30,text='Build',onClick=function() -- Create an actionable GUI button with the specified placement, label and callback.
            local item=safeItem(slot); if not item then return end -- Keep item local to this scope so callbacks do not accidentally overwrite shared globals.
            if editingPack then -- Run this branch only when its explicit state, selection or availability condition holds.
                if not db.categories[editingPack] then return end -- Handle a guard/terminal case immediately instead of continuing with unsuitable state.
                C.setPackMember(db,editingPack,item.id,not db.categories[editingPack][item.id]) -- Delegate this operation to the pure data helper so UI actions share the same validated behaviour.
                persist() -- Commit the changed picker data and capture an undo step only if tracked data actually changed.
                slot.action:setText(db.categories[editingPack][item.id] and 'Remove' or 'Add') -- Refresh the displayed label to reflect the current binding, choices or result count.
                count:setText('Editing '..editingPack..' | '..C.categoryCount({categories={[editingPack]=db.categories[editingPack]}},editingPack,byId)..' loaded buildings in this pack') -- Refresh the displayed label to reflect the current binding, choices or result count.
            else selectPlacement(item) end -- Apply the fallback branch when the preceding condition did not match.
        end} -- Close the current function, callback, conditional or loop at this nesting level.
        if currentMode=='kit' then -- Run this branch only when its explicit state, selection or availability condition holds.
            slot.row:addButton{x=-138,y=4,width=66,height=30,text='Packs',onClick=function() -- Create an actionable GUI button with the specified placement, label and callback.
                local item=safeItem(slot);if item then assignCategories(item,reload) end -- Keep item local to this scope so callbacks do not accidentally overwrite shared globals.
            end} -- Close the current function, callback, conditional or loop at this nesting level.
        end -- Close the current function, callback, conditional or loop at this nesting level.
        slot.favourite=slot.row:addButton{x=-138,y=44,width=66,height=30,text='Fav',onClick=function() -- Create an actionable GUI button with the specified placement, label and callback.
            local item=safeItem(slot); if item then toggle(db.favourites,item.id); reload() end -- Keep item local to this scope so callbacks do not accidentally overwrite shared globals.
        end} -- Close the current function, callback, conditional or loop at this nesting level.
        slot.hide=slot.row:addButton{x=-68,y=44,width=64,height=30,text='Hide',onClick=function() -- Create an actionable GUI button with the specified placement, label and callback.
            local item=safeItem(slot); if item then toggle(db.hidden,item.id); reload() end -- Keep item local to this scope so callbacks do not accidentally overwrite shared globals.
        end} -- Close the current function, callback, conditional or loop at this nesting level.
        slots[#slots+1]=slot -- Retain this fixed reusable row slot; its callbacks consult the slot's current bound item.
    end -- Close the current function, callback, conditional or loop at this nesting level.
    local function bind(slot,index) -- Rebind an existing visible result slot to a new catalogue item, including its callbacks and metadata.
        local item=matches[index] -- Keep item local to this scope so callbacks do not accidentally overwrite shared globals.
        if not item then -- Run this branch only when its explicit state, selection or availability condition holds.
            slot.item=nil;slot.index=index;slot.row:setVisible(false);return -- Show only valid currently bound content, hiding unused or unavailable slots.
        end -- Close the current function, callback, conditional or loop at this nesting level.
        slot.item=item;slot.index=index -- Update slot.item for the current operation; subsequent controls/filters read this state.
        slot.row:setPosition(0,(index-1)*rowHeight) -- Move the recycled control to the logical position of its currently bound item or guide line.
        slot.row:setVisible(true) -- Show only valid currently bound content, hiding unused or unavailable slots.
        slot.title:setText(item.title) -- Refresh the displayed label to reflect the current binding, choices or result count.
        slot.info:setText(item.w..'x'..item.h..' | '..item.kind..' | '..tostring(wealthLabel(item))) -- Refresh the displayed label to reflect the current binding, choices or result count.
        local source=item.plugin and (item.pack=='local' and 'Local pack' or 'Store #'..item.pack) or 'Built-in' -- Keep source local to this scope so callbacks do not accidentally overwrite shared globals.
        slot.source:setText(source..' | Height '..tostring(item.height or 'unknown')..' | '..money(item.price)) -- Refresh the displayed label to reflect the current binding, choices or result count.
        -- Static atlas handles avoid allocating a native draft drawer per row.
        local frame=call(item.draft,'getPreviewFrame',nil,1) or call(item.draft,'getFrame',nil,1) -- Keep frame local to this scope so callbacks do not accidentally overwrite shared globals.
        slot.icon:setVisible(frame~=nil) -- Show only valid currently bound content, hiding unused or unavailable slots.
        if frame then slot.icon:setIcon(frame) end -- Bind the current static thumbnail frame without creating a native placement selector.
        slot.action:setText(editingPack and -- Refresh the displayed label to reflect the current binding, choices or result count.
            (db.categories[editingPack][item.id] and 'Remove' or 'Add') or 'Build') -- Choose Remove for a direct member, Add for a nonmember in edit mode, and Build outside membership editing.
        slot.favourite:setText(db.favourites[item.id] and 'Unfav' or 'Fav') -- Refresh the displayed label to reflect the current binding, choices or result count.
        slot.hide:setText(db.hidden[item.id] and 'Restore' or 'Hide') -- Refresh the displayed label to reflect the current binding, choices or result count.
    end -- Close the current function, callback, conditional or loop at this nesting level.
    updateRows=function(force) -- Define the update Rows callback used by its surrounding screen.
        local offset=math.abs(list:getShiftY()) -- Keep offset local to this scope so callbacks do not accidentally overwrite shared globals.
        local first=math.min(math.max(1,#matches-poolSize+1),math.max(1,math.floor(offset/rowHeight))) -- Keep first local to this scope so callbacks do not accidentally overwrite shared globals.
        for i,slot in ipairs(slots) do -- Iterate the indicated entries; ipairs visits ordered rows, while pairs visits ID-keyed maps.
            local index=first+i-1 -- Keep index local to this scope so callbacks do not accidentally overwrite shared globals.
            if force or slot.index~=index or slot.item~=matches[index] then bind(slot,index) end -- Run this branch only when its explicit state, selection or availability condition holds.
        end -- Close the current function, callback, conditional or loop at this nesting level.
    end -- Close the current function, callback, conditional or loop at this nesting level.
    rebuild=function(text) -- Define the rebuild callback used by its surrounding screen.
        previous=text;state.query=text -- Update previous for the current operation; subsequent controls/filters read this state.
        matches={};local q=text:lower() -- Update matches for the current operation; subsequent controls/filters read this state.
        for _,item in ipairs(base) do -- Iterate the indicated entries; ipairs visits ordered rows, while pairs visits ID-keyed maps.
            if q=='' or item.title:lower():find(q,1,true) or item.id:lower():find(q,1,true) then -- Run this branch only when its explicit state, selection or availability condition holds.
                matches[#matches+1]=item -- Append the candidate that passed the live literal text search to the displayed result metadata.
            end -- Close the current function, callback, conditional or loop at this nesting level.
        end -- Close the current function, callback, conditional or loop at this nesting level.
        extent=math.max(52,#matches*rowHeight) -- Update extent for the current operation; subsequent controls/filters read this state.
        content:setSize(list:getClientWidth(),extent) -- Update the full content extent so the viewport and scrollbar cover all matching entries.
        list:setShiftY(0) -- Adjust list scrolling; zero returns to the start after a changed search or Top action.
        empty:setVisible(#matches==0) -- Show only valid currently bound content, hiding unused or unavailable slots.
        count:setText(#matches..' buildings match search | '..#base..' pass other filters') -- Refresh the displayed label to reflect the current binding, choices or result count.
        updateRows(true) -- Refresh the list/search presentation using existing working state and reusable row bindings.
    end -- Close the current function, callback, conditional or loop at this nesting level.
    p:addButton{x=-96,y=0,width=96,height=30,text='Clear search',onClick=function() search:setText('');rebuild('') end} -- Create an actionable GUI button with the specified placement, label and callback.
    p:addButton{x=0,y=-68,width=140,height=30,text='Back to filters',onClick=showMain} -- Create an actionable GUI button with the specified placement, label and callback.
    if editingPack then -- Run this branch only when its explicit state, selection or availability condition holds.
        p:addButton{x=148,y=-68,width=145,height=30,text='Add all matches',onClick=function() -- Create an actionable GUI button with the specified placement, label and callback.
            -- Bulk operations use all filtered metadata, never just the visible row pool.
            local added=C.addToPack(db,editingPack,matches);persist();Debug.toast('Added '..added..' new buildings.');updateRows(true) -- Explain the result or validation issue through a short in-game message.
        end} -- Close the current function, callback, conditional or loop at this nesting level.
        p:addButton{x=301,y=-68,width=170,height=30,text='Finish pack editing',onClick=finishPackEdit} -- Create an actionable GUI button with the specified placement, label and callback.
    else -- Apply the fallback branch when the preceding condition did not match.
        p:addButton{x=148,y=-68,width=190,height=30,text='Random favourite',onClick=function() -- Create an actionable GUI button with the specified placement, label and callback.
            local chosen=C.random(catalog,state,db,available) -- Keep chosen local to this scope so callbacks do not accidentally overwrite shared globals.
            if chosen then selectPlacement(chosen) else Debug.toast('No available favourites match these filters.') end -- Explain the result or validation issue through a short in-game message.
        end} -- Close the current function, callback, conditional or loop at this nesting level.
    end -- Close the current function, callback, conditional or loop at this nesting level.
    p:addLabel{x=0,y=-34,width=325,height=28,text='Budget: '..tostring(db.budgetMax or 'Unlimited')..' | Undo affects picker data.'} -- Display explanatory text or metadata without changing filter or saved-data state.
    historyButtons(p,-34,browse,330) -- Expose the shared ten-step picker-data history and its scope explanation on this screen.
    scrollbar(p,'$tenjiku_building_scrollbar',function() return list end,function() return extent end,62,76) -- Link the visible scrollbar to this list and its full logical content extent.
    rebuild(state.query) -- Refresh the list/search presentation using existing working state and reusable row bindings.
end -- Close the current function, callback, conditional or loop at this nesting level.

local function presetMenu() -- Manage named copies of ordinary filters; the global budget stays separate.
    dismiss() -- Close the currently owned dialog/help before constructing the next screen.
    local d=GUI.createDialog{title='Saved presets',width=480,height=400}; activeDialog=d -- Create this screen with an explicit title and bounded dimensions, then retain its owned handle.
    local p=d.content -- Keep p local to this scope so callbacks do not accidentally overwrite shared globals.
    p:addButton{x=0,y=0,width=-1,height=32,text='Save current filters as preset',onClick=function() -- Create an actionable GUI button with the specified placement, label and callback.
        input('Save preset','Use a name such as Japanese small homes. Existing names are updated.','',function(name) -- Request a text value and route accepted or cancelled input to the correct screen.
            name=name:match('^%s*(.-)%s*$') -- Update name for the current operation; subsequent controls/filters read this state.
            if name=='' or #name>80 then Debug.toast('Use a name between 1 and 80 characters.'); presetMenu(); return end -- Explain the result or validation issue through a short in-game message.
            db.presets[name]=C.copy(state); persist(); presetMenu() -- Commit the changed picker data and capture an undo step only if tracked data actually changed.
        end,presetMenu) -- Return to the preset manager when the preset-name input is cancelled.
    end} -- Close the current function, callback, conditional or loop at this nesting level.
    local list=p:addListBox{id='$tenjiku_preset_results',x=0,y=40,width=-22,height=-40} -- Create a scrollable viewport for the current option list or recycled content.
    local names={}; for name in pairs(db.presets) do names[#names+1]=name end; table.sort(names) -- Keep names local to this scope so callbacks do not accidentally overwrite shared globals.
    for _,value in ipairs(names) do local name=value -- Iterate the indicated entries; ipairs visits ordered rows, while pairs visits ID-keyed maps.
        local row=list:addCanvas{height=42} -- Create a layout/content container; its logical dimensions can exceed the visible viewport.
        row:addLabel{x=2,y=0,width=-148,height=40,text=name} -- Display explanatory text or metadata without changing filter or saved-data state.
        row:addButton{x=-144,y=5,width=66,height=30,text='Load',onClick=function() -- Create an actionable GUI button with the specified placement, label and callback.
            state=C.normalise(db.presets[name]); showMain() -- Update state for the current operation; subsequent controls/filters read this state.
        end} -- Close the current function, callback, conditional or loop at this nesting level.
        row:addButton{x=-74,y=5,width=70,height=30,text='Delete',onClick=function() -- Create an actionable GUI button with the specified placement, label and callback.
            db.presets[name]=nil; persist(); presetMenu() -- Commit the changed picker data and capture an undo step only if tracked data actually changed.
        end} -- Close the current function, callback, conditional or loop at this nesting level.
    end -- Close the current function, callback, conditional or loop at this nesting level.
    if #names==0 then list:addLabel{height=52,text='No saved presets yet.'} end -- Display explanatory text or metadata without changing filter or saved-data state.
    p:addButton{x=0,y=-32,width=130,height=30,text='Back',onClick=showMain} -- Create an actionable GUI button with the specified placement, label and callback.
    historyButtons(p,-32,presetMenu,140) -- Expose the shared ten-step picker-data history and its scope explanation on this screen.
    scrollbar(p,'$tenjiku_presets_scroll',function() return list end,function() return math.max(52,#names*42) end,40,40) -- Link the visible scrollbar to this list and its full logical content extent.
end -- Close the current function, callback, conditional or loop at this nesting level.

showMain=function() -- Render the current mode's basic controls and optionally expanded advanced filters.
    if currentMode=='normal' then state.customCategories={} end -- Run this branch only when its explicit state, selection or availability condition holds.
    if not catalog then scan() end -- Run this branch only when its explicit state, selection or availability condition holds.
    C.pruneSourceFilters(state,knownPacks,knownTypes) -- Delegate this operation to the pure data helper so UI actions share the same validated behaviour.
    dismiss() -- Close the currently owned dialog/help before constructing the next screen.
    local d=GUI.createDialog{title=editingPack and ('Pack Kit - Add to '..editingPack) or (currentMode=='normal' and 'Normal Selection' or 'Pack Kit - Building filters'),width=470,height=490}; activeDialog=d -- Create this screen with an explicit title and bounded dimensions, then retain its owned handle.
    local p=d.content -- Keep p local to this scope so callbacks do not accidentally overwrite shared globals.
    local quickW,quickH=state.fitW,state.fitH -- Keep quick W,quick H local to this scope so callbacks do not accidentally overwrite shared globals.
    if state.sizeMode=='Exact sizes' and C.count(state.sizes)==1 then -- Run this branch only when its explicit state, selection or availability condition holds.
        for key,v in pairs(state.sizes) do if v then quickW,quickH=key:match('^(%d+)x(%d+)$') end end -- Iterate the indicated entries; ipairs visits ordered rows, while pairs visits ID-keyed maps.
    end -- Close the current function, callback, conditional or loop at this nesting level.
    p:addLabel{x=0,y=0,width=18,height=30,text='X'} -- Display explanatory text or metadata without changing filter or saved-data state.
    local x=p:addTextField{x=20,y=0,width=60,height=30,text=tostring(quickW)} -- Create an editable field; the associated callback validates or applies its text.
    p:addLabel{x=88,y=0,width=18,height=30,text='Y'} -- Display explanatory text or metadata without changing filter or saved-data state.
    local y=p:addTextField{x=108,y=0,width=60,height=30,text=tostring(quickH)} -- Create an editable field; the associated callback validates or applies its text.
    p:addButton{x=176,y=0,width=-34,height=30,text='Apply exact X x Y',onClick=function() -- Create an actionable GUI button with the specified placement, label and callback.
        local w,a=C.integer(x:getText()); local h,b=C.integer(y:getText()) -- Keep w,a local to this scope so callbacks do not accidentally overwrite shared globals.
        if not a or not b then Debug.toast('Enter positive whole numbers for X and Y.'); return end -- Explain the result or validation issue through a short in-game message.
        state.fitW,state.fitH=w,h; state.sizes={[w..'x'..h]=true}; state.sizeMode='Exact sizes'; showMain() -- Store validated quick dimensions, replace all exact choices with this footprint and refresh the main panel.
    end} -- Close the current function, callback, conditional or loop at this nesting level.
    helpButton(p,{x=-30,y=0,width=28,height=30},'Exact X x Y','Enter positive whole numbers for the footprint in tiles, then Apply. This replaces the size filter with that exact size. Tile Tetris starts here.') -- Provide contextual help using a small square button and the matching topic description.
    local list=p:addListBox{id='$tenjiku_main_filters',x=0,y=40,width=-22,height=-82} -- Create a scrollable viewport for the current option list or recycled content.
    local rows=0 -- Keep rows local to this scope so callbacks do not accidentally overwrite shared globals.
    local function row(text,action) -- Create one compact action row and, where supplied, its adjacent contextual-help button.
        rows=rows+1 -- Update rows for the current operation; subsequent controls/filters read this state.
        local line=list:addCanvas{height=34} -- Create a layout/content container; its logical dimensions can exceed the visible viewport.
        line:addButton{x=0,y=0,width=-34,height=32,text=text,onClick=action} -- Create an actionable GUI button with the specified placement, label and callback.
        local title,message=helpFor(text) -- Keep title,message local to this scope so callbacks do not accidentally overwrite shared globals.
        helpButton(line,{x=-30,y=0,width=28,height=32},title,message) -- Provide contextual help using a small square button and the matching topic description.
    end -- Close the current function, callback, conditional or loop at this nesting level.
    if editingPack then -- Run this branch only when its explicit state, selection or availability condition holds.
        row('Finish adding buildings to: '..editingPack,finishPackEdit) -- Add this named control to the current screen and wire it to its dedicated editor/action.
    elseif currentMode=='kit' then -- Handle the next mutually exclusive case when preceding conditions did not apply.
        row('Back to your building packs',categoryManager) -- Add this named control to the current screen and wire it to its dedicated editor/action.
    end -- Close the current function, callback, conditional or loop at this nesting level.
    local function filterLabel(inc,exc) -- Summarise unrestricted includes and explicit exclusions without ambiguous zero-selected wording.
        return (not C.any(inc) and (C.any(exc) and 'All except blocked' or 'All allowed') or ('Only '..C.count(inc)..' chosen'))..' / '..(C.count(exc)==0 and 'None blocked' or (C.count(exc)..' blocked')) -- Return the computed value or finish this branch immediately, leaving callers to handle the result.
    end -- Close the current function, callback, conditional or loop at this nesting level.
    row('Theons budget: '..tostring(db.budgetMax or 'Unlimited'),function() editBudget(showMain) end) -- Add this named control to the current screen and wire it to its dedicated editor/action.
    row('Size: '..sizeLabel(),sizeMenu) -- Add this named control to the current screen and wire it to its dedicated editor/action.
    row('Types: '..filterLabel(state.typesIn,state.typesOut),function() -- Add this named control to the current screen and wire it to its dedicated editor/action.
        multi('Building types',types,state.typesIn,state.typesOut) -- Open a searchable multi-choice list with the supplied include, exclude or membership sets.
    end) -- Close the current function, callback, conditional or loop at this nesting level.
    row('Installed plugins: '..filterLabel(state.packsIn,state.packsOut),function() -- Add this named control to the current screen and wire it to its dedicated editor/action.
        multi('Installed plugin packs',packs,state.packsIn,state.packsOut) -- Open a searchable multi-choice list with the supplied include, exclude or membership sets.
    end) -- Close the current function, callback, conditional or loop at this nesting level.
    row('Source: '..state.source,function() -- Add this named control to the current screen and wire it to its dedicated editor/action.
        options('Building source',{'All sources','Built-in only','Plugins only'},function(v) state.source=v; showMain() end) -- Open a single-choice editor and apply only the option the player clicks.
    end) -- Close the current function, callback, conditional or loop at this nesting level.
    row('Name / ID: '..(state.query=='' and 'No text filter' or state.query),function() -- Add this named control to the current screen and wire it to its dedicated editor/action.
        input('Building name or ID','Substring search; blank restores all names.',state.query,function(value) state.query=value; showMain() end) -- Request a text value and route accepted or cancelled input to the correct screen.
    end) -- Close the current function, callback, conditional or loop at this nesting level.
    row(advancedOpen and 'Fewer filters' or 'More filters',function() advancedOpen=not advancedOpen;showMain() end) -- Add this named control to the current screen and wire it to its dedicated editor/action.
    if advancedOpen then -- Run this branch only when its explicit state, selection or availability condition holds.
        row('Include swapped dimensions: '..(state.rotate and 'Yes' or 'No'),function() state.rotate=not state.rotate; showMain() end) -- Add this named control to the current screen and wire it to its dedicated editor/action.
        row('Wealth: '..(C.any(state.wealth) and C.count(state.wealth)..' chosen levels only' or 'All levels allowed'),function() -- Add this named control to the current screen and wire it to its dedicated editor/action.
            multi('RCI wealth (T / TT / TTT)',{{key='0',label='T'},{key='1',label='TT'},{key='2',label='TTT'}},state.wealth,nil) -- Open a searchable multi-choice list with the supplied include, exclude or membership sets.
        end) -- Close the current function, callback, conditional or loop at this nesting level.
        row('Visual height: '..((not state.heightMin and not state.heightMax) and 'No limit' or (tostring(state.heightMin or 0)..' to '..tostring(state.heightMax or 'unlimited')..' game units')),editHeight) -- Add this named control to the current screen and wire it to its dedicated editor/action.
        row('Collection: '..state.collection,function() -- Add this named control to the current screen and wire it to its dedicated editor/action.
            options('Browse collection',{'All buildings','Favourites','Recent picks','Hidden items'},function(v) -- Open a single-choice editor and apply only the option the player clicks.
                state.collection=v;if v=='Recent picks' then state.sort='Most recent' end;showMain() -- Update state.collection for the current operation; subsequent controls/filters read this state.
            end) -- Close the current function, callback, conditional or loop at this nesting level.
        end) -- Close the current function, callback, conditional or loop at this nesting level.
        row('Availability: '..(state.availability=='All' and 'Available + unavailable' or state.availability),function() -- Add this named control to the current screen and wire it to its dedicated editor/action.
            options('Native placement availability',{'All','Available only','Unavailable only'},function(v) state.availability=v;showMain() end) -- Open a single-choice editor and apply only the option the player clicks.
        end) -- Close the current function, callback, conditional or loop at this nesting level.
        row('Show hidden items: '..(state.showHidden and 'Yes' or 'No'),function() state.showHidden=not state.showHidden;showMain() end) -- Add this named control to the current screen and wire it to its dedicated editor/action.
        row('Sort: '..state.sort,function() -- Add this named control to the current screen and wire it to its dedicated editor/action.
            options('Sort matching buildings',{'Name A-Z','Name Z-A','Footprint','Height','Price','Plugin source','Most recent'},function(v) state.sort=v;showMain() end) -- Open a single-choice editor and apply only the option the player clicks.
        end) -- Close the current function, callback, conditional or loop at this nesting level.
        row('Presets: '..C.count(db.presets)..' saved',presetMenu) -- Add this named control to the current screen and wire it to its dedicated editor/action.
    end -- Close the current function, callback, conditional or loop at this nesting level.
    scrollbar(p,'$tenjiku_main_scroll',function() return list end,function() return rows*34 end,40,82) -- Link the visible scrollbar to this list and its full logical content extent.
    p:addButton{x=0,y=-72,width=-34,height=32,text=editingPack and 'Choose buildings for pack' or 'Browse matching buildings',onClick=browse} -- Create an actionable GUI button with the specified placement, label and callback.
    helpButton(p,{x=-30,y=-72,width=28,height=32},'Browse, reset and refresh','Browse shows matching buildings. Reset restores ordinary filters; your global Theons budget stays active. Refresh rescans loaded buildings after plugin changes. Home switches tools and offers Undo/Redo. A tidy desk does not empty your wallet.') -- Provide contextual help using a small square button and the matching topic description.
    p:addButton{x=0,y=-34,width=150,height=30,text='Reset filters',onClick=function() state=C.defaults(); showMain() end} -- Create an actionable GUI button with the specified placement, label and callback.
    p:addButton{x=158,y=-34,width=150,height=30,text='Refresh catalog',onClick=function() scan(); showMain() end} -- Create an actionable GUI button with the specified placement, label and callback.
    p:addButton{x=316,y=-34,width=120,height=30,text='Home',onClick=showHome} -- Create an actionable GUI button with the specified placement, label and callback.
end -- Close the current function, callback, conditional or loop at this nesting level.

local guideLines={ -- Embedded manual text, already wrapped into display lines; no external file-loader API is required.
    "NIKHIL'S BUILDING TOOLS", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Release notes and complete feature guide | Steam / desktop", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "01. WHAT THIS TOOL DOES", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Find loaded buildings by footprint, building type, source plugin, name,", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "wealth, height, collection, placement availability and listed price. Place", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "individual buildings through TheoTown's normal placement tool. Create your", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "own named collections for districts such as Japanese Homes, New York CBD", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "or China CBD.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "The tool organises and selects existing building definitions. It does not", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "supply new building artwork, install dependencies, change population or", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "jobs, bypass charges, change zoning growth or automatically generate a", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "district. A personal pack is a saved list of building IDs, not a new", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "distributable building plugin.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "02. RELEASE NOTES", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "The public name is now Nikhil's Building Tools. The ZIP, installation", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "folder, JSON file and Lua script use Nikhils_Building_Tools. Existing", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "internal identifiers and storage keys stay compatible so previously saved", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "packs, favourites, hidden items, recent picks, presets and budget can be", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "reused.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Home now includes Release Notes & Feature Guide. This opens the complete", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "scrollable guide you are reading. Its visible scrollbar covers the entire", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "document. The viewer recycles a small set of text rows rather than", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "creating a control for every line. Back to Home returns to the two modes", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "without altering filters or saved data.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "The compact home rows and square help buttons remain. The Pack Building", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Kit help button is aligned with its own row. Detailed building previews", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "remain removed.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "03. PREVIOUS RELEASES", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "v18: Missing or disabled plugin sources and buildings disappear from", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "current listings. Personal pack counts use loaded members. Missing", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "source/type filters are cleared from active views and preset copies. Build", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "rechecks the catalogue before placement. Saved references survive", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "reinstatement.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "v17: Empty-state labels describe the actual effect. Source/type filters", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "say All allowed and None blocked. Search counts state their units. Empty", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "exact sizes explicitly match nothing. Pack membership, pack browsing and", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "wealth use their own wording. Clear search is separate from clearing", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "filter choices.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "v16: Both mode buttons match the budget row's height. Home became shorter", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "with tighter spacing and matching square question-mark buttons.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "v15: Home help buttons became square to avoid native button skins", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "extending beyond the dialog edge.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "v14: Home split into Normal Selection and Pack Building Kit; advanced", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "filters collapse behind More filters. Added question-mark help, global", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Theons budget and picker-data Undo/Redo. History was capped at ten actions", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "in either direction.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "v13: Removed the larger detailed-preview dialog, descriptions/price", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "preview panels and frame-variant navigation. Build and Random favourite", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "open normal placement directly.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "v12: Replaced unbounded building-result controls with twelve recycled", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "rows. Search and bulk Add still cover every match. Small static thumbnails", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "avoid creating native placement drawers merely to display results.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "v7-v11 foundation: Native building selection, size/source/type filtering,", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "favourites, hidden items, recent picks, presets, personal packs with", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "descriptions and nested folders, searchable lists and direct sidebar", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "access.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "04. INSTALLING OR UPDATING", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Close TheoTown. Remove the old Tenjiku_Size_Picker installation folder and", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "replace it with the Nikhils_Building_Tools folder in this ZIP. Also", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "replace an existing Nikhils_Building_Tools folder when updating. Keep only", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "one copy installed; leaving both creates duplicate controllers with shared", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "internal IDs.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Use your TheoTown plugins directory. On Windows this is commonly", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Documents/TheoTown/plugins; redirected Documents folders can change the", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "location. The manifest targets desktop TheoTown 1.12.18 or newer with Lua", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "support. Restart after updating, enter a city and click the Kermit icon on", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "the left toolbar.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Renaming the public files does not deliberately reset saved picker data.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Removing the plugin folder does not remove buildings already placed in", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "your city. The tool has no building artwork dependencies beyond the", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "original plugins you choose from.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "05. KERMIT BUTTON AND HOME", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "The Kermit face uses a transparent pixel icon on TheoTown's normal blue", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "toolbar skin. It appends beneath existing left-sidebar buttons. If a", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "replacement sidebar prevents that integration, a compatibility button", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "appears near the lower-left area. A native icon can be used if the custom", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "frame cannot be obtained.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Home contains Normal Selection, Pack Building Kit, Theons budget, Release", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Notes & Feature Guide, and Undo/Redo. Normal Selection searches and places", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "buildings. Pack Building Kit manages your personal collections. Question", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "marks open explanations; Got it closes that explanation while keeping the", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "underlying screen intact.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Opening Home rescans loaded definitions. Normal mode and kit mode keep", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "separate working filter states. Entering Normal Selection clears", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "personal-pack restrictions so a previously browsed district pack does not", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "silently constrain your ordinary catalogue. It also collapses advanced", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "controls; their existing settings still apply.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "06. NORMAL SELECTION: BASIC CONTROLS", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "X and Y are tile counts for a building footprint: X is width and Y is", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "depth. Enter positive whole numbers and click Apply exact X x Y. This", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "replaces the size selection with one exact footprint. It does not select", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "an empty map area or move the camera.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Basic rows contain Theons budget, Size, Types, Installed plugins, Source", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "and Name / ID. More filters reveals additional settings; Fewer filters", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "hides those controls without clearing them. Browse matching buildings", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "opens the filtered catalogue.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Reset filters restores the ordinary defaults, including exact 1x1 size,", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "all types/sources, no text search, no wealth/height limit, all buildings", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "collection, all availability, hidden items omitted and Name A-Z sorting.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "It does not delete packs, favourites, hidden IDs, presets or recent picks.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "It does not clear the global Theons budget.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Refresh catalog rescans loaded definitions. Home returns to the mode", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "selector. Filter panels have scrollbars so controls remain reachable when", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "the advanced rows are expanded.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "07. HOW FILTERS COMBINE", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Different filter families combine with AND. A building must pass size AND", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "type AND plugin-source AND source category AND wealth AND height AND", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "collection AND availability AND search AND budget. A valid building can", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "disappear because another active filter rejects it.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Several include choices inside one family combine with OR. Including two", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "sources admits buildings from either source. Exclusions block their", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "matching entries. Choosing Include clears Exclude for that same entry;", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "choosing Exclude clears Include. Empty type/source include sets allow", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "every type/source except explicit exclusions.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "The Source row can still narrow an included-source list: Built-in only", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "plus an included downloaded source can produce zero matches. Clear search", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "removes text only. Allow all clears includes and exclusions in that", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "selector. Other filter families remain active.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "08. EXACT SIZES AND MANUAL MULTIPLE SIZES", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Exact sizes lists discovered footprints and any footprints already", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "selected. Include toggles each footprint; several may be chosen together.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Done uses that selection. No chosen exact footprints means no buildings", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "match; it does not mean any size. Select none intentionally empties the", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "footprint set.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Enter several sizes accepts examples such as 1x1, 2x2, 2x3. Commas or", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "semicolons separate footprints. Dimension separators x, X and * are", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "accepted. Spaces and leading zeroes are normalised; repeated footprints", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "are deduplicated. Empty input, fractions, zero, negative dimensions and", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "malformed entries are rejected.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Numeric footprint fields accept positive whole numbers up to 2147483647.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "This input ceiling does not imply buildings of that size exist or that", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "TheoTown can place them. A manually selected footprint can remain valid as", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "a search even when no loaded building currently uses it.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "09. SIZE RANGE, PLOT FIT AND SWAPPED DIMENSIONS", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Size range sets independent minimum and maximum X and Y, inclusively. X", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "1-3 and Y 1-3 includes footprints such as 1x1, 1x3, 2x2 and 3x3. It is a", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "per-dimension range, not an area range. A 1x6 building does not qualify", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "merely because its area is below 3x3.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Fits within plot sets a maximum width and depth. A 4x6 plot accepts", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "footprints no wider than 4 and no deeper than 6. It does not test terrain,", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "roads, occupancy, access, empty space or the actual tile under your", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "cursor.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Include swapped dimensions also tests the footprint with width and depth", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "exchanged. For a 2x3 exact choice, a 3x2 definition can qualify. It does", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "not add rotation frames or force buildings to rotate. Native orientation", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "and original plugin capabilities determine what can actually be placed.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Any size removes footprint restrictions. Use it explicitly when you want", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "the whole catalogue rather than clearing exact choices.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "10. BUILDING TYPES", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Types are discovered from loaded, eligible building definitions. Examples", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "can include residential, commercial, industrial, parks and services;", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "actual names depend on the definitions installed. Select several Include", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "or Exclude choices, or Allow all to remove this family of restrictions.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "All types allowed / None blocked means this filter family is unrestricted,", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "not that zero buildings are allowed. Only N chosen types means those type", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "choices form the permitted group. A separate search-count line reports how", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "many type entries match the selector's own search, not how many buildings", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "will be placed.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "11. INSTALLED PLUGIN SOURCES", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Installed plugins lists loaded plugin sources discovered through the game", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "API, plus built-in game buildings. Store entries use their numeric Store", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "ID, an e.g. draft title and a count explicitly labelled buildings. The", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "example title is not necessarily the actual store pack title.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Non-building plugins can appear with zero eligible buildings. That does", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "not mean their plugin is missing: shaders, animals and similar content can", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "have no selectable buildings. Counts here describe eligible catalogue", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "definitions, not matches under your current size, wealth, budget or search", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "filters.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Local ZIP or unidentified plugins are grouped together when the API", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "supplies no distinct positive store ID. The tool cannot reliably separate", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "these into named original ZIPs. Built-in game buildings are a separate", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "source entry. Source independently switches between All sources, Built-in", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "only and Plugins only.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "All sources allowed / None blocked means no source restriction. All other", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "sources allowed with a blocked count means exclusion-only filtering. Only", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "N chosen sources restricts to those included sources, subject to the", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "remaining filters.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "12. SEARCHES, COUNTS AND CLEAR BUTTONS", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Name / ID and the building-results search perform literal,", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "case-insensitive substring matching on a building's displayed name or ID.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "They do not interpret regular expressions, infer architectural style or", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "search an original plugin's full store description. A word must occur in", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "the name or ID to match.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Building-results search updates the working text filter and resets the", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "result scroll position to the top. Clear search empties this text only. It", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "does not reset size, budget or any other filter. The result count", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "separates buildings matching text from buildings passing the other", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "filters.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Search inside a type/source/size/wealth selection list narrows the options", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "visible in that list; it does not change which options you previously", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "chose. Clear search restores the list. Choices outside the currently", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "visible search results remain active.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "The personal-pack manager searches pack paths/names, not every member", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "building or its description. Its count reports matching personal", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "packs/folders out of the saved total. No search matches differs from", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "having no packs created yet.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "13. GLOBAL THEONS BUDGET", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Enter a maximum listed construction price from Home or the filter panel in", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "either mode. A non-negative whole number from 0 to 2147483647 is accepted.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Blank input or the word unlimited, case-insensitively, removes the cap.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Invalid input keeps the form open and leaves the old value unchanged.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "The limit is inclusive: a 300 cap accepts a known listed price of 300.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Zero is valid. Buildings with unknown prices are excluded while a cap is", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "active; Unlimited permits unknown prices. The filter checks a building", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "definition's base price, not maintenance, your current funds or final", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "tile-specific charges.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "The cap is global across both modes, personal-pack browsing, bulk Add", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "candidates and Random favourite. It persists between sessions and cities.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Reset filters does not clear it. A preset does not capture or override it.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Undo/Redo can reverse changes to it.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "A budget does not bypass native affordability or placement rules and does", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "not deduct money merely by filtering. It is a search ceiling, not an", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "automatic spending allowance.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "14. WEALTH LEVELS", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "For residential, commercial and industrial buildings, T maps to level 0,", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "TT to level 1 and TTT to level 2. Include several levels to allow their", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "union. No wealth choices means all wealth levels are allowed and non-RCI", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "buildings may remain in results.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Selecting specific wealth levels excludes definitions that are not RCI or", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "have no matching level. This is a filter on the original definition, not a", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "wealth upgrade or population editor. The main row states whether all", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "levels or only chosen levels are allowed.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "15. VISUAL HEIGHT", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Enter minimum and/or maximum reported build height in non-negative whole", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "game units. Bounds are inclusive. Blank minimum leaves the lower bound", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "open; blank maximum leaves the upper bound open. Both blank means no", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "height limit. Minimum greater than maximum is rejected.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Unknown heights are excluded when either bound is active. These units are", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "the game's reported visual-height units, not a count of floors. The tool", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "does not estimate a tower's storeys from its image or change its height.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "16. FAVOURITES AND HIDDEN BUILDINGS", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Fav saves a building ID as a favourite. Unfav removes that mark.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Collection > Favourites restricts results to saved favourites while", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "retaining all other filters. Favourites are shared across cities and saved", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "between sessions.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Hide hides a building from ordinary picker results only. It does not", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "disable its original plugin, remove it from the city, affect zoning growth", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "or hide it in the game's other menus. Show hidden items includes hidden", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "definitions in ordinary results. Collection > Hidden items specifically", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "lists hidden buildings for restoring them.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Restore removes the hidden mark. A hidden favourite remains hidden in", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "ordinary Favourites results until hidden items are allowed.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Hidden/favourite changes are undoable picker-data edits. A missing", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "original plugin cannot be made visible simply by marking its ID as a", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "favourite.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "17. RECENT PICKS", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "The tool keeps up to 100 unique recently selected building IDs. Selecting", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "the same ID again moves it to the front without duplicating it. Collection", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "> Recent picks sets Most recent sorting, but you can choose another sort", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "afterwards.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "A recent pick means the native placement tool was successfully activated.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "It is not confirmation that you actually constructed the building.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Cancelling placement can still leave the building in Recent. Recent picks", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "remain saved across sessions; their updates are not Undo/Redo actions.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Missing definitions disappear from visible recent results. Existing", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "references can become visible again if the original definitions return.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Size, search, budget, hidden settings and other filters still apply to", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Recent.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "18. AVAILABILITY AND NATIVE BUILD", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Availability chooses all definitions, Available only or Unavailable only,", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "using the native placement selector's current selectability check. This", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "can reflect mode, unlocks, funds and manual-building rules. It does not", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "establish that a specific map tile is valid.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Build closes the picker and defers the handoff, then checks the current", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "city and current catalogue before creating the normal placement selector.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Changing or leaving the city cancels that pending handoff. A missing", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "definition is rejected; an unselectable one produces an unavailable", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "message instead of bypassing game rules.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Native placement still determines costs, access, terrain, occupied tiles", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "and supported variants. Build starts placement; it does not automatically", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "place the building. The tool does not replace TheoTown's construction", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "controls.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Explicit availability filtering and Random favourite can create native", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "selectors for checks and may take longer over large catalogues. Ordinary", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "unfiltered list thumbnails do not create a selector for every row.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "19. BUILDING RESULT ROWS AND SCROLLING", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Rows display a small static thumbnail when available, a building name,", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "footprint, type, RCI wealth or non-RCI status, source, reported height and", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "listed price. Unknown height and price are labelled explicitly. A bad or", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "missing thumbnail is isolated so that the rest of the catalogue can remain", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "usable.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Normal Selection rows offer Build, Fav/Unfav and Hide/Restore. Kit rows", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "also offer Packs for assigning the building to personal collections.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "During membership editing, Add/Remove replaces Build: it changes pack", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "membership, not the city.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "The browser reuses twelve rows as you scroll. The visible scrollbar", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "represents all matching buildings, not just those twelve. Search operates", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "on the full matching metadata list. Bulk Add covers every matching entry,", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "including entries below the current viewport.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "The larger detailed-preview window was removed. There is no large image,", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "detailed-description dialog, frame navigator or variant selector provided", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "by this tool. The original plugin and native game controls handle", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "supported variants.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "20. RANDOM FAVOURITE", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Random favourite chooses among loaded, visible-to-the-picker favourite", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "definitions that pass all current filters and are currently selectable.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "The global budget applies. It opens the normal placement tool for the", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "chosen building; it does not build automatically.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "If there are no eligible favourites, a message explains that none match.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Collection filters also remain active: choosing Hidden items or Recent", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "picks can further narrow which favourites qualify. There is no", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "configurable weighting or no-repeat district generator.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "21. SORTING", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Name A-Z and Name Z-A order displayed names without case sensitivity.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Footprint orders by width times depth, not width alone. Height and Price", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "sort known numeric values first and unknown values afterwards. Plugin", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "source orders source keys. Most recent uses the recent-pick ranking, with", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "IDs not in Recent afterwards.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Where the primary sort value ties, the tool uses name and then ID for a", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "stable ordering. Sorting changes display order; it does not change which", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "definitions pass your filters or alter the original game build menu.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "22. SAVED FILTER PRESETS", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Presets > Save current filters as preset stores the current filter", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "combination. Use a non-empty name up to 80 UTF-8 bytes. Leading/trailing", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "whitespace is trimmed. Saving an existing name replaces that preset, which", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "can be undone.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Presets include size mode, exact footprints, range/fit bounds,", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "swapped-dimension setting, type/source includes and excludes, source", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "category, wealth, height, collection, availability, hidden visibility,", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "sort, text search and any active personal-pack restriction in kit mode.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "The global budget remains separate. A preset is not a membership list and", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "does not clone buildings. Load restores a separate working copy; later", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "filter edits do not mutate the saved original. Missing source/type", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "restrictions are removed from that working copy.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Normal mode deliberately clears personal-pack restrictions when showing", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "its filters. Use the kit to browse named collections. Delete in Presets", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "deletes only that saved filter combination. Deletion is undoable and does", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "not delete buildings or personal packs.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "23. PACK BUILDING KIT: CREATE A PACK", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Click New pack, enter a name and optional short description, then Apply.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Names can describe styles or districts, but the tool does not infer those", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "styles. You choose actual buildings yourself. Names must be unique and", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "cannot be empty.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "A description is limited to 300 UTF-8 bytes. A pack path is limited to 120", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "UTF-8 bytes and six slash-separated levels. Multi-byte characters consume", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "more than one byte. Leading/trailing whitespace in each path component is", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "trimmed. Empty components such as Japan//Homes are rejected.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Japan/Homes creates a nested Homes pack under Japan. Parent folders are", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "created automatically. A parent can also have directly saved buildings of", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "its own. Personal packs are saved game-wide and shared across cities.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "24. PACK COUNTS AND NESTED FOLDERS", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "A personal-pack entry counts currently loaded building IDs from that pack", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "and all descendants, deduplicated. If one building is saved in Japan and", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Japan/Homes, browsing Japan still lists that building once. Counts do not", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "promise that current budget, hidden settings or availability will let", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "every member appear in results.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Missing definitions do not contribute to loaded counts. Your pack name", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "remains editable even with zero loaded members. Saved references remain", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "privately so reinstating the exact original IDs can restore membership. A", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "renamed or replaced original definition with a different ID is a different", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "building.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Counts for plugin sources, personal packs and search results describe", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "different things. Source counts concern eligible definitions supplied by a", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "source; personal-pack counts concern loaded member IDs; result counts", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "concern definitions passing your working filters and search.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "25. ADDING AND REMOVING PACK MEMBERS", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Open Edit for a personal pack, then Add / remove buildings (with filters).", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "The membership filter panel starts with any size so an old size choice", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "does not hide candidates. The global budget still applies. Choose optional", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "filters, then Choose buildings for pack.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Add saves the building's ID directly into the edited pack. Remove removes", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "that direct membership. Changes save immediately, without a final Save", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "button. The current row stays available so you can correct the choice, and", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Undo/Redo is available for recent changes.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "The same building may belong to several packs. Removing it from one pack", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "does not remove it from another pack or the city. A building inherited", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "from a subpack remains in a parent's union until its descendant membership", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "is removed; edit the relevant subpack to remove that inherited membership.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Finish pack editing returns to the pack's editor and restores the", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "preceding kit filter state. Switching to Normal Selection exits", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "membership-edit mode; changes already made remain saved.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "26. BULK ADD AND MEMBERSHIP ASSIGNMENT", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Add all matches in the membership browser adds every building passing the", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "current filters and live text search, not merely the visible rows.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Repeated additions do not duplicate IDs. The entire operation is one", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "undoable data change if it adds anything.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Add all current filtered matches in the pack editor uses the current", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "working filters. It does not mean every installed building irrespective of", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "filters. Review the candidate search before using bulk operations,", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "especially with Any size.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Packs on a kit result row opens that individual building's membership", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "list. Include toggles membership in each personal pack. Done saves the", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "chosen assignments. Remove from all clears the choices in that dialog;", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Done applies the removal. This does not remove the building definition or", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "placed copies.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Membership summaries say Not assigned to any pack or Assigned to N", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "personal packs. A list search does not clear memberships outside the", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "visible rows. Parent display counts can include subpacks even when the", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "direct membership checkbox is off.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "27. BROWSING PERSONAL PACKS", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Browse in the pack manager or Browse all buildings in pack opens that", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "collection for manual placement. It starts a clean any-size view", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "constrained to the chosen pack, including descendants. The budget remains", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "global and ordinary hidden items remain hidden by default.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Browse pack by building type lists the loaded types represented inside", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "that pack. Choosing one restricts the clean pack view to that type. An", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "empty pack has no types to choose until eligible members are loaded.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Browse several packs opens a searchable multi-choice list. Select at least", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "one and press Done to browse the combined union. Shared members appear", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "once. No packs chosen returns you to the manager with a message; it does", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "not unexpectedly open the entire catalogue.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "These packs do not create special zoning paint. Build is still a manual", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "selection action for an individual building. Architectural consistency", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "comes from the member choices you save.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "28. RENAME, DESCRIPTION AND DELETE", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Edit pack name / description changes the chosen collection's metadata.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Renaming a parent moves its descendants under the new path and updates", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "matching active/preset references. Name collisions and moving a folder", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "into its own subtree are rejected.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Delete pack and subpacks opens an explicit confirmation. Cancel keeps", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "everything. Delete removes that personal collection and descendants, not", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "installed assets, buildings already placed or membership in other packs.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "References in active filters and presets are updated as part of that", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "change.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Pack creation, membership, description edits, renaming and deletion can be", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "undone within the session history limit. No changes are exported as a new", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "plugin archive automatically.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "29. UNDO AND REDO: TEN ACTIONS EACH WAY", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Undo reverses the most recent stored picker-data edit. Redo reapplies an", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "undone edit. Each direction retains at most ten actions. A new data edit", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "clears the Redo branch. Repeating a no-op such as adding an already-added", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "member does not create a different data snapshot.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "History covers personal packs and descriptions, memberships, pack", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "creation/rename/deletion, favourites, hidden IDs, saved presets and the", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "global budget. Bulk changes are captured together. The buttons act on the", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "latest eligible change across those features, not just the screen", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "containing the button.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "History is session-only and not deliberately stored across plugin reloads.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Switching cities without unloading the script need not reset it. Saved", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "data itself persists. Ordinary filter edits, scrolling, opening screens,", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "search navigation, recent-pick updates and city construction are outside", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "this history.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Undoing a preset deletion restores its saved settings but does not", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "automatically load it. Undoing a pack change restores stored pack data; it", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "does not rewind every ordinary working-filter choice. Undoing", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "favourite/hidden changes does not change the city. Use TheoTown's own", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "tools for placed buildings.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "30. MISSING, DISABLED OR REINSTALLED PLUGINS", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "The current catalogue is rebuilt when opening Home or building results, on", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "a fresh city catalogue and through Refresh catalog. Only loaded, visible,", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "non-template building definitions with positive footprints become building", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "results. Source entries come from loaded plugin drafts, including", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "non-building sources.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Missing buildings disappear from results, Favourites, Recent, Hidden-item", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "results, personal pack browsing and available counts. Missing source", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "entries disappear from the installed-source selector. Active", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "included/excluded source and type choices that no longer exist are cleared", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "so they cannot trap a search.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Saved source choices inside a preset are retained privately, but loading", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "it prunes missing choices from its active copy. Your manual size choices", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "remain searches even if no current building matches. Original", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "personal-pack names remain editable; missing members remain only saved", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "references.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "If a definition disappears after a result row was drawn but before", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "deferred Build runs, the handoff checks the current catalogue and refuses", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "to create a selector for it. These checks are not a guarantee against", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "unrelated errors in an original plugin or the native game.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "31. SAVING AND DATA SCOPE", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Packs, descriptions, memberships, favourites, hidden IDs, recent picks,", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "presets and budget use TheoTown's persistent storage. They are shared", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "across cities. Internal legacy keys are intentionally retained through the", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "public rename to avoid deliberately abandoning existing data.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Normal and kit working-filter states are held in memory. Use named presets", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "to preserve a search across sessions; ordinary filter navigation is not", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "itself an automatically saved preset. Undo/Redo history is also in memory.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "The plugin does not copy external artwork into personal packs. Original", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "downloaded or local source plugins must remain installed and enabled.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Restoring a reference requires the same building ID. Sharing or backing up", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "a district pack through a dedicated export/import UI is not currently", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "implemented.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "32. PERFORMANCE, TROUBLESHOOTING AND LIMITS", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Building results use bounded recycled rows, static thumbnails and metadata", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "filtering. A mocked 10,000-building catalogue test checks scrolling to the", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "final entry, correct recycled button targets, full-list search and bulk", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Add without creating a native drawer per row.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "The source/type multi-choice lists and personal-pack manager use ordinary", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "scrollable lists, not the twelve-row building pool. Rescanning and", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "explicit availability checks can still cost time with large installations.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "This tool does not promise zero lag or eliminate bugs in other plugins.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "For empty results: check exact-size selection, all include/exclude", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "families, source category, wealth, height, collection, hidden settings,", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "text and budget. Clear search affects only text. Reset filters restores", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "1x1 and leaves budget active. Choose Any size and Unlimited explicitly for", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "a broad search.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "A zero-building source may be a non-building plugin. A personal pack with", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "zero loaded buildings may have disabled dependencies. A pack count larger", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "than its visible results may reflect hidden items, budget or other", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "filters. No result count is a promise of valid map tiles.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Automated validation uses a real Lua interpreter with mocked TheoTown", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "APIs. TheoTown itself was not available for native UI, game persistence or", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "placement verification. The detailed guide documents current behaviour and", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "limitations; unsupported features are not silently enabled by reading it.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "33. QUICK WORKED EXAMPLE", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "To place a small affordable home: open Normal Selection, apply 1x1,", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "include the Residential type, set a 500 Theons budget, browse and click", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Build on a result. If none appear, widen size or budget and inspect other", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "active filters. Construction still uses the normal game rules.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "To organise a Japanese district: open Pack Building Kit, create", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Japan/Homes with a description, open Add / remove buildings, filter", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "source/name/size as useful, choose candidates and Add them. Finish", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "editing, then Browse the pack and Build members one at a time. Add another", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "collection such as Japan/Shops when ready.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "To recover from an accidental bulk addition: click Undo once immediately.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "To recover from a missing source: re-enable the original plugin and reopen", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Home or Refresh catalog. Its saved personal memberships can reappear once", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "the original building IDs are loaded.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "END OF GUIDE", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "Nikhil's Building Tools. Build a skyline, keep the filing cabinet", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
    "civilised.", -- Embedded feature-guide text; rendered as a logical line by the scrollable manual viewer.
} -- Finish the current table or GUI/API argument block.
showGuide=function() -- Display the embedded full manual with a bounded text-row pool and a scrollbar spanning all lines.
    dismiss() -- Close the currently owned dialog/help before constructing the next screen.
    local d=GUI.createDialog{title="Nikhil's Building Tools - Guide",width=620,height=520};activeDialog=d -- Create this screen with an explicit title and bounded dimensions, then retain its owned handle.
    local p=d.content -- Keep p local to this scope so callbacks do not accidentally overwrite shared globals.
    p:addLabel{x=0,y=0,width=-1,height=28,text='Release history + complete feature explanations'} -- Display explanatory text or metadata without changing filter or saved-data state.
    local lineHeight=20 -- Fixed manual-line height used consistently for content extent and virtual row positions.
    local extent=#guideLines*lineHeight -- Represent the entire manual in scrollbar space, including off-screen lines.
    local list,updateRows -- Keep list,update Rows local to this scope so callbacks do not accidentally overwrite shared globals.
    list=p:addListBox{id='$nikhil_building_tools_guide',x=0,y=32,width=-22,height=-42, -- Create a scrollable viewport for the current option list or recycled content.
        onUpdate=function() if updateRows then updateRows() end end} -- Define the on Update callback used by its surrounding screen.
    local content=list:addCanvas{x=0,y=0,width=-1,height=extent} -- Create a layout/content container; its logical dimensions can exceed the visible viewport.
    local slots={} -- Store reusable row controls rather than allocating a new GUI tree for each logical result.
    for i=1,28 do slots[i]=content:addLabel{x=0,y=(i-1)*lineHeight,width=-1,height=lineHeight,text=''} end -- Display explanatory text or metadata without changing filter or saved-data state.
    updateRows=function() -- Define the update Rows callback used by its surrounding screen.
        local offset=math.abs(list:getShiftY()) -- Keep offset local to this scope so callbacks do not accidentally overwrite shared globals.
        local first=math.min(math.max(1,#guideLines-#slots+1),math.max(1,math.floor(offset/lineHeight)+1)) -- Keep first local to this scope so callbacks do not accidentally overwrite shared globals.
        for i,node in ipairs(slots) do -- Iterate the indicated entries; ipairs visits ordered rows, while pairs visits ID-keyed maps.
            local index=first+i-1 -- Keep index local to this scope so callbacks do not accidentally overwrite shared globals.
            node:setVisible(guideLines[index]~=nil) -- Show only valid currently bound content, hiding unused or unavailable slots.
            node:setPosition(0,(index-1)*lineHeight) -- Move the recycled control to the logical position of its currently bound item or guide line.
            node:setText(guideLines[index] or '') -- Refresh the displayed label to reflect the current binding, choices or result count.
        end -- Close the current function, callback, conditional or loop at this nesting level.
    end -- Close the current function, callback, conditional or loop at this nesting level.
    p:addButton{x=0,y=-34,width=150,height=30,text='Back to Home',onClick=showHome} -- Create an actionable GUI button with the specified placement, label and callback.
    p:addButton{x=160,y=-34,width=100,height=30,text='Top',onClick=function() list:setShiftY(0);updateRows() end} -- Create an actionable GUI button with the specified placement, label and callback.
    p:addLabel{x=272,y=-34,width=-1,height=28,text='Scroll for all 33 topics and release notes.'} -- Display explanatory text or metadata without changing filter or saved-data state.
    scrollbar(p,'$nikhil_building_tools_guide_scroll',function() return list end,function() return extent end,32,42) -- Link the visible scrollbar to this list and its full logical content extent.
    updateRows() -- Refresh the list/search presentation using existing working state and reusable row bindings.
end -- Close the current function, callback, conditional or loop at this nesting level.

showHome=function() -- Rescan definitions and present the compact two-mode selector, budget, guide and history controls.
    scan() -- Rebuild current loaded definitions and clear obsolete active source/type restrictions.
    dismiss() -- Close the currently owned dialog/help before constructing the next screen.
    local d=GUI.createDialog{title="Nikhil's Building Tools",width=450,height=302};activeDialog=d -- Create this screen with an explicit title and bounded dimensions, then retain its owned handle.
    local p=d.content -- Keep p local to this scope so callbacks do not accidentally overwrite shared globals.
    p:addButton{x=0,y=0,width=-38,height=30,text='Normal Selection',onClick=function() -- Create an actionable GUI button with the specified placement, label and callback.
        if currentMode=='kit' then kitState=editingReturnState or state else normalState=state end -- Run this branch only when its explicit state, selection or availability condition holds.
        editingPack=nil;editingReturnState=nil -- Update editing Pack for the current operation; subsequent controls/filters read this state.
        currentMode='normal';state=normalState;state.customCategories={};advancedOpen=false -- Update current Mode for the current operation; subsequent controls/filters read this state.
        showMain() -- Render the current mode's filter panel using its active working state.
    end} -- Close the current function, callback, conditional or loop at this nesting level.
    helpButton(p,{x=-32,y=0,width=30,height=30},'Normal Selection','Find a building using size, name, type or installed plugin filters, then Build to place it. More filters opens the fancy stuff. A building buffet with a search bar.') -- Provide contextual help using a small square button and the matching topic description.
    p:addLabel{x=0,y=34,width=-1,height=28,text='Find buildings by size, name, type or installed plugin; place them.'} -- Display explanatory text or metadata without changing filter or saved-data state.
    p:addButton{x=0,y=74,width=-38,height=30,text='Pack Building Kit',onClick=function() -- Create an actionable GUI button with the specified placement, label and callback.
        if currentMode=='normal' then normalState=state;state=kitState end -- Run this branch only when its explicit state, selection or availability condition holds.
        currentMode='kit' -- Update current Mode for the current operation; subsequent controls/filters read this state.
        if not catalog then scan() end -- Run this branch only when its explicit state, selection or availability condition holds.
        categoryManager() -- Open the personal-pack manager while retaining the kit's current working filters.
    end} -- Close the current function, callback, conditional or loop at this nesting level.
    helpButton(p,{x=-32,y=74,width=30,height=30},'Pack Building Kit','Create named personal collections from installed buildings. Add members, organise subpacks and browse them for manual placement. These collections do not control what grows in zones. District playlists, zero record deal required.') -- Provide contextual help using a small square button and the matching topic description.
    p:addLabel{x=0,y=108,width=-1,height=28,text='Create, edit and browse your own district building collections.'} -- Display explanatory text or metadata without changing filter or saved-data state.
    p:addButton{x=0,y=148,width=-38,height=30,text='Theons budget: '..tostring(db.budgetMax or 'Unlimited'),onClick=function() editBudget(showHome) end} -- Create an actionable GUI button with the specified placement, label and callback.
    helpButton(p,{x=-32,y=148,width=30,height=30},'Theons budget',helpTopics['Theons budget']) -- Provide contextual help using a small square button and the matching topic description.
    p:addButton{x=0,y=190,width=-1,height=30,text='Release Notes & Feature Guide',onClick=showGuide} -- Create an actionable GUI button with the specified placement, label and callback.
    historyButtons(p,-34,showHome,0) -- Expose the shared ten-step picker-data history and its scope explanation on this screen.
end -- Close the current function, callback, conditional or loop at this nesting level.

function script:init() loadData() end -- Load saved picker data during script initialisation without resetting compatible legacy IDs.
function script:buildCityGUI() -- Attach the Kermit button to the native sidebar or use the compatibility fallback.
    inCity=true -- Update in City for the current operation; subsequent controls/filters read this state.
    local existing=GUI.get(buttonId); if existing then existing:delete() end -- Dispose the previous owned list/control before replacing it, avoiding stacked stale GUI trees.
    -- Kermit pixel icon on the native toolbar skin.
    local iconDraft=Draft.getDraft('$tenjiku_size_picker_kermit_icon_v1') -- Keep icon Draft local to this scope so callbacks do not accidentally overwrite shared globals.
    local buttonIcon=iconDraft and iconDraft:getFrame(1) or Icon.REGION_SPLIT or Icon.CITY -- Keep button Icon local to this scope so callbacks do not accidentally overwrite shared globals.
    local normalFrame=Icon.NP_BLUE_BUTTON or (NinePatch and NinePatch.BLUE_BUTTON) -- Keep normal Frame local to this scope so callbacks do not accidentally overwrite shared globals.
    local downFrame=Icon.NP_BLUE_BUTTON_PRESSED or (NinePatch and NinePatch.BLUE_BUTTON_PRESSED) -- Keep down Frame local to this scope so callbacks do not accidentally overwrite shared globals.
    -- Append to the native left sidebar rather than floating over the city.
    local sidebar=GUI.get('sidebarLine') -- Keep sidebar local to this scope so callbacks do not accidentally overwrite shared globals.
    if sidebar then -- Run this branch only when its explicit state, selection or availability condition holds.
        local ok,part=pcall(function() return sidebar:getFirstPart() end) -- Protect the native/API operation so a failed method can be handled without aborting the tool.
        if ok and part then -- Run this branch only when its explicit state, selection or availability condition holds.
            local size=30 -- Keep size local to this scope so callbacks do not accidentally overwrite shared globals.
            local sized,width=pcall(function() return part:getChild(2):getWidth() end) -- Protect the native/API operation so a failed method can be handled without aborting the tool.
            if sized and type(width)=='number' and width>0 then size=width end -- Run this branch only when its explicit state, selection or availability condition holds.
            part:addButton{id=buttonId,width=size,height=size,icon=buttonIcon, -- Create an actionable GUI button with the specified placement, label and callback.
                frameDefault=normalFrame,frameDown=downFrame,onClick=showHome} -- Handle this button click using its supplied closure; capture the current item/state before acting.
            return -- Stop this callback now; the required handoff or feedback has already been handled.
        end -- Close the current function, callback, conditional or loop at this nesting level.
    end -- Close the current function, callback, conditional or loop at this nesting level.
    -- Compatibility fallback when another UI replaces the standard sidebar.
    GUI.getRoot():addButton{id=buttonId,x=4,y=-82,width=32,height=32,icon=buttonIcon, -- Create an actionable GUI button with the specified placement, label and callback.
        frameDefault=normalFrame,frameDown=downFrame,onClick=showHome} -- Handle this button click using its supplied closure; capture the current item/state before acting.
end -- Close the current function, callback, conditional or loop at this nesting level.

function script:enterCity() epoch=epoch+1; inCity=true; catalog=nil end -- Increment the city epoch and invalidate cached definitions before building the next city view.
function script:leaveCity() editingPack=nil;editingReturnState=nil;inCity=false; epoch=epoch+1; dismiss(); catalog=nil; persist() end -- Cancel pending city actions, close dialogs, invalidate the catalogue and persist picker data.
function script:disable() -- Clean up the owned toolbar/dialog UI and save data without touching placed buildings.
    editingPack=nil;editingReturnState=nil;inCity=false; epoch=epoch+1; dismiss(); persist() -- Commit the changed picker data and capture an undo step only if tracked data actually changed.
    local b=GUI.get(buttonId); if b then b:delete() end -- Dispose the previous owned list/control before replacing it, avoiding stacked stale GUI trees.
end -- Close the current function, callback, conditional or loop at this nesting level.
function script:unload() self:disable(); catalog=nil end -- Run disable cleanup and discard the remaining cached catalogue.
