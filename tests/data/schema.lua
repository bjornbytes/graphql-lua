local types = require 'graphql.types'
local schema = require 'graphql.schema'

local dogCommand = types.enum({
  name = 'DogCommand',
  values = {
    SIT = true,
    DOWN = true,
    HEEL = true
  }
})

local pet = types.interface({
  name = 'Pet',
  fields = {
    name = types.string.nonNull,
    nickname = types.int
  }
})

local dog = types.object({
  name = 'Dog',
  interfaces = { pet },
  fields = {
    name = types.string,
    nickname = types.string,
    barkVolume = types.int,
    doesKnowCommand = {
      kind = types.boolean.nonNull,
      arguments = {
        dogCommand = dogCommand.nonNull
      }
    },
    isHouseTrained = {
      kind = types.boolean.nonNull,
      arguments = {
        atOtherHomes = types.boolean
      }
    },
    complicatedField = {
      kind = types.boolean,
      arguments = {
        complicatedArgument = types.inputObject({
          name = 'complicated',
          fields = {
            x = types.string,
            y = types.integer,
            z = types.inputObject({
              name = 'alsoComplicated',
              fields = {
                x = types.string,
                y = types.integer
              }
            })
          }
        })
      }
    }
  }
})

local sentient = types.interface({
  name = 'Sentient',
  fields = {
    name = types.string.nonNull
  }
})

local alien = types.object({
  name = 'Alien',
  interfaces = sentient,
  fields = {
    name = types.string.nonNull,
    homePlanet = types.string
  }
})

local human = types.object({
  name = 'Human',
  fields = {
    name = types.string.nonNull
  }
})

local cat = types.object({
  name = 'Cat',
  fields = {
    name = types.string.nonNull,
    nickname = types.string,
    meowVolume = types.int
  }
})

local catOrDog = types.union({
  name = 'CatOrDog',
  types = {cat, dog}
})

local dogOrHuman = types.union({
  name = 'DogOrHuman',
  types = {dog, human}
})

local humanOrAlien = types.union({
  name = 'HumanOrAlien',
  types = {human, alien}
})

local query = types.object({
  name = 'Query',
  fields = {
    dog = {
      kind = dog,
      args = {
        name = {
          kind = types.string
        }
      }
    },
    cat = cat,
    pet = pet,
    sentient = sentient,
    catOrDog = catOrDog,
    humanOrAlien = humanOrAlien
  }
})

return schema.create({
  query = query
})
