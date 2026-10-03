-- @LICENSE (MIT)
-- CitizenFX DataView implementation for Matrix/Buffer operations (e.g. ImGuizmo)
-- Reference: https://github.com/citizenfx/lua/blob/luaglm-dev/cfx/lua.h

if not DataView then
    DataView = setmetatable({
        EndBig = ">",
        EndLittle = "<",
        Types = {
            Int8 = { code = "i1" },
            Uint8 = { code = "I1" },
            Int16 = { code = "i2" },
            Uint16 = { code = "I2" },
            Int32 = { code = "i4" },
            Uint32 = { code = "I4" },
            Int64 = { code = "i8" },
            Uint64 = { code = "I8" },
            Float32 = { code = "f", size = 4 },
            Float64 = { code = "d", size = 8 },
            LuaInt = { code = "j" },
            UluaInt = { code = "J" },
            LuaNum = { code = "n" },
            String = { code = "z", size = -1 },
        },
        FixedTypes = {
            String = { code = "c" },
            Int = { code = "i" },
            Uint = { code = "I" },
        },
    }, {
        __call = function(_, length)
            return DataView.ArrayBuffer(length)
        end
    })
    DataView.__index = DataView

    function DataView.ArrayBuffer(length)
        return setmetatable({
            blob = string.blob(length),
            length = length,
            offset = 1,
            cangrow = true,
        }, DataView)
    end

    function DataView.Wrap(blob)
        return setmetatable({
            blob = blob,
            length = blob:len(),
            offset = 1,
            cangrow = true,
        }, DataView)
    end

    function DataView:Buffer() return self.blob end
    function DataView:ByteLength() return self.length end
    function DataView:ByteOffset() return self.offset end

    function DataView:SubView(offset, length)
        return setmetatable({
            blob = self.blob,
            length = length or self.length,
            offset = 1 + offset,
            cangrow = false,
        }, DataView)
    end

    local function packblob(self, offset, value, code)
        local packed = self.blob:blob_pack(offset, code, value)
        if self.cangrow or packed == self.blob then
            self.blob = packed
            self.length = packed:len()
            return true
        else
            return false
        end
    end

    for label, datatype in pairs(DataView.Types) do
        if not datatype.size then
            datatype.size = string.packsize(datatype.code)
        elseif datatype.size >= 0 and string.packsize(datatype.code) ~= datatype.size then
            error(string.format("Pack size of %s (%d) does not match cached length: (%d)", label, string.packsize(datatype.code), datatype.size))
        end

        DataView["Get" .. label] = function(self, offset, endian)
            local code = datatype.code
            local o = self.offset + offset
            return self.blob:blob_unpack(o, code)
        end

        DataView["Set" .. label] = function(self, offset, value, endian)
            local code = datatype.code
            local o = self.offset + offset
            packblob(self, o, value, code)
            return self
        end
    end

    for label, datatype in pairs(DataView.FixedTypes) do
        DataView["GetFixed" .. label] = function(self, offset, typelen, endian)
            local code = datatype.code .. tostring(typelen)
            local o = self.offset + offset
            return self.blob:blob_unpack(o, code)
        end

        DataView["SetFixed" .. label] = function(self, offset, typelen, value, endian)
            local code = datatype.code .. tostring(typelen)
            local o = self.offset + offset
            packblob(self, o, value, code)
            return self
        end
    end
end
