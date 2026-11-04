-- Sends anyone who falls under the map (or glitches through the floor) back to spawn.
local Players = game:GetService("Players")
local FLOOR_Y = -40

while true do
	task.wait(1)
	local spawnPad = workspace:FindFirstChild("SpawnLocation")
	for _, player in Players:GetPlayers() do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root and root.Position.Y < FLOOR_Y then
			root.AssemblyLinearVelocity = Vector3.zero
			local target = spawnPad and spawnPad.CFrame or CFrame.new(0, 10, 125)
			player.Character:PivotTo(target + Vector3.new(0, 5, 0))
		end
	end
end
