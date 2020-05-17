----------------------------------------------------------------------------------------------------
-- SnowContractNode
----------------------------------------------------------------------------------------------------
-- Purpose:  Node specifying node contract shapes
--
-- Copyright (c) Realismus Modding, 2019
----------------------------------------------------------------------------------------------------

SnowContractNode = {}

---Handle a node with an SnowContractNode onCreate
function SnowContractNode:create(mission, nodeId, contracts)
    contracts:addNewSnowContractNode(nodeId)
end
