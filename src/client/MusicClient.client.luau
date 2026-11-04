--[[
    MusicClient — quiet background music on a loop.

    The playlist plays in order and repeats. Volume is kept low so it sits under the game sounds.
    To change songs, edit PLAYLIST (audio asset IDs).
]]

local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local PLAYLIST = {
    79513526076598,  -- Wi-Fi In The Fridge (Instrumental): catchy, goofy
    108387120827216, -- we spoke in a dream: dreamy
    129693897951452, -- Steady Focus (Warm Pads): slow, hypnotic pads
}
local VOLUME = 0.2

local group = Instance.new("SoundGroup")
group.Name = "Music"
group.Volume = VOLUME
group.Parent = SoundService

local sound = Instance.new("Sound")
sound.Name = "BackgroundMusic"
sound.SoundGroup = group
sound.Volume = 1
sound.Parent = SoundService

local index = 0
local function playNext()
    index = index % #PLAYLIST + 1
    sound.SoundId = "rbxassetid://" .. PLAYLIST[index]
    sound.TimePosition = 0
    sound:Play()
end
sound.Ended:Connect(playNext)

-- start quietly after the game loads in
task.wait(2)
group.Volume = 0
playNext()
TweenService:Create(group, TweenInfo.new(3), { Volume = VOLUME }):Play()
