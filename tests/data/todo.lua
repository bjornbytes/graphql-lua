local types = require 'graphql.types'
local schema = require 'graphql.schema'

local clients = {
  [1] = { id = 1, name = "Microsoft" },
  [2] = { id = 2, name = "Oracle'" },
  [3] = { id = 3, name = "Apple" }
}

local projects = {
  [1] = { id = 1, name = "Windows 7", client_id = 1 },
  [2] = { id = 2, name = "Windows 10", client_id = 1 },
  [3] = { id = 3, name = "IOS", client_id = 3 },
  [4] = { id = 4, name = "OSX", client_id = 3 }
}

local tasks = {
  [1] = { id = 1, name = "Design w7", project_id = 1 },
  [2] = { id = 2, name = "Code w7", project_id = 1 },
  [3] = { id = 3, name = "Unassigned Task", project_id = 1 },
  [4] = { id = 4, name = "Design w10", project_id = 2 },
  [5] = { id = 5, name = "Code w10", project_id = 2 },
  [6] = { id = 6, name = "Design IOS", project_id = 3 },
  [7] = { id = 7, name = "Code IOS", project_id = 3 },
  [8] = { id = 8, name = "Design OSX", project_id = 4 },
  [9] = { id = 9, name = "Code OSX", project_id = 4 }
}

local getObjectById = function(store, id)
  return store[id]
end

local getObjectsByKey = function(store, key, value)
  local results = {}
  for k,v in pairs(store) do
    if v[key] == value then
      table.insert(results, v)
    end
  end
  return results
end

local getClientById = function (id) return getObjectById(clients, id) end
local getProjectById = function (id) return getObjectById(projects, id) end
local getTaskById = function (id) return getObjectById(clients, id) end
local getProjectByClientId = function (id) return getObjectsByKey(projects, "client_id") end
local getTasksByProjectId = function (id) return getObjectsByKey(tasks, "project_id") end


local project, client, task
client = types.object {
  name = 'Client',
  description = 'Client',
  fields = function()
    return {
      id = { kind = types.nonNull(types.int), description = 'The id of the client.'},
      name = { kind = types.string, description = 'The name of the client.'},
      projects = {
        kind = types.list(project),
        description = 'projects',
        resolve = function(client, arguments)
          return getProjectByClientId(client.id)
        end
      }
    }
  end
}

project = types.object {
  name = 'Project',
  description = 'Project',
  fields = function()
    return {
      id = { kind = types.nonNull(types.int), description = 'The id of the project.'},
      name = { kind = types.string, description = 'The name of the project.'},
      client_id = { kind = types.nonNull(types.int), description = 'client id'},
      client = {
        kind = client,
        description = 'client',
        resolve = function(project)
          return getClientById(project.client_id)
        end
      },
      tasks = {
        kind = types.list(task),
        description = 'tasks',
        resolve = function(project, arguments)
          return getTasksByProjectId(project.id)
        end
      }
    }
  end
}

task = types.object {
  name = 'Task',
  description = 'Task',
  fields = function()
    return {
      id = { kind = types.nonNull(types.int), description = 'The id of the task.'},
      name = { kind = types.string, description = 'The name of the task.'},
      project_id = { kind = types.nonNull(types.int), description = 'project id'},
      project = {
        kind = project,
        description = 'project',
        resolve = function(task)
          return getProjectById(task.project_id)
        end
      }
    }
  end
}


-- Create a schema
return schema.create {
  query = types.object {
    name = 'Query',
    fields = {
      client = {
        kind = client,
        arguments = {
          id = {
            kind = types.nonNull(types.int),
            description = 'id of the client'
          }
        },
        resolve = function(rootValue, arguments)
          return getClientById(arguments.id)
        end
      },

      project = {
        kind = project,
        arguments = {
          id = {
            kind = types.nonNull(types.int),
            description = 'id of the project'
          }

        },
        resolve = function(rootValue, arguments)
          return getProjectById(arguments.id)
        end
      },

      task = {
        kind = task,
        arguments = {
          id = {
            kind = types.nonNull(types.int),
            description = 'id of the task'
          }

        },
        resolve = function(rootValue, arguments)
          return getTaskById(arguments.id)
        end
      }
    }
  }
}
