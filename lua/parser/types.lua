---@class DotnetSolution
---@field name string
---@field path string
---@field projects DotnetProject[]
---@field folders DotnetFolder[]

---@class DotnetProjectReference
---@field name string
---@field path string
---@field guid? string
---@field project? DotnetProject

---@class DotnetPackageReference
---@field name string
---@field version? string
---@field private_assets? string
---@field include_assets? string
---@field exclude_assets? string

---@class DotnetDiagnostics
---@field errors integer
---@field warnings integer
---@field information integer
---@field hints integer

---@class DotnetProject
---@field type string
---@field name string
---@field path string
---@field dir string
---@field guid? string
---@field references DotnetProjectReference[]
---@field packages DotnetPackageReference[]
---@field diagnostics DotnetDiagnostics?

---@class DotnetFolder
---@field name string
---@field path string
---@field parent_path? string
---@field guid? string
---@field parent_guid? string
---@field children DotnetFolder[]
---@field projects DotnetProject[]
