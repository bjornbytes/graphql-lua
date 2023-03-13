local log = require('log')

local VERSION = require('graphql.version')

return setmetatable({
    _VERSION = VERSION,
}, {
    __index = function(_, key)
        if key == 'VERSION' then
            log.warn("require('graphql').VERSION is deprecated, " ..
                     "use require('graphql')._VERSION instead.")
            return VERSION
        end

        return nil
    end
})
