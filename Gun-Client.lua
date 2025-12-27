local RS = game:GetService("ReplicatedStorage") -- Locates to ReplicatedStorage
local InterfaceModule = require(RS.Modules:WaitForChild("InterfaceModule")) -- Locates to the InterfaceModule script
local TweenService = game:GetService("TweenService") -- Locates to TweenService
local Players = game:GetService("Players") -- Locates to Players
local UserInputService = game:GetService("UserInputService") -- Locates to UserInputService
local ContentProvider = game:GetService("ContentProvider") -- Locates to ContentProvider
local Debris = game:GetService("Debris") -- Locates to Debris

local player = Players.LocalPlayer -- Locates to the LocalPlayer
local char = player.Character or player.CharacterAdded:Wait() -- Locates to the Character
local CharHumanoid = char:FindFirstChildOfClass("Humanoid") -- Locates to the Humanoid
local mouse = player:GetMouse() -- Locates to the Client's mouse
local WeaponsGui = player.PlayerGui:WaitForChild("WeaponsGui") -- Locates to the Weapons GUI
local GunFrame = WeaponsGui:WaitForChild("Gun") -- Locates to the Gun UI Frame
local Bar = GunFrame.TimerBar.Bar -- Locates to the progress bar
local Bullets = GunFrame.Bullets -- Locates to the ammo text
local Tool = script.Parent -- Locates to the Gun Tool
local ShootEvent = RS.Events:WaitForChild("Shoot") -- Locates to the shoot remote event
local IndicatorEvent = RS.Events:WaitForChild("Indicator") -- Locates to the damage remote event

local ShootPart = script:WaitForChild("ShootPart") -- Locates to the impact effect part
local IndicatorPart = RS:WaitForChild("IndicatorPart") -- Locates to the floating number part
local HitSound = script:WaitForChild("HitSound") -- Locates to the hit sound effect

local Equipped = true -- Stores whether the gun is currently equipped
local currentAnimTrack -- Stores the currently playing animation track
local AnimationsPreloaded = false -- Tracks if animations have been preloaded
local SoundsPreloaded = false -- Tracks if sounds have been preloaded

local GunState = { -- Defines all possible gun states
	Idle = "Idle", -- Gun is idle and ready
	Firing = "Firing", -- Gun is firing
	Reloading = "Reloading" -- Gun is reloading
}

local state = GunState.Idle -- Stores the current gun state
local reloadTime = 2 -- Time taken to reload
local fireCooldown = 0.4 -- Time between shots
local ammo = 10 -- Current ammo count
local maxAmmo = 10 -- Maximum ammo count
local lastFire = 0 -- Time of last shot
local CachedParams = nil -- Cached raycast parameters

local function setState(newState)
	state = newState -- Updates the gun state
end

local function preloadAssets()
	local ViewModel = workspace.CurrentCamera:WaitForChild("ViewModel", 3) -- Locates the viewmodel

	if not AnimationsPreloaded then
		local animations = {} -- Stores animations to preload

		for _, anim in ipairs(ViewModel:WaitForChild("AnimationFolder"):GetChildren()) do
			if anim:IsA("Animation") then
				table.insert(animations, anim) -- Adds animation to preload list
			end
		end

		if #animations > 0 then
			ContentProvider:PreloadAsync(animations) -- Preloads animations
		end

		AnimationsPreloaded = true -- Marks animations as loaded
	end

	if not SoundsPreloaded then
		local sounds = {} -- Stores sounds to preload

		for _, s in ipairs(ViewModel:WaitForChild("SoundsFolder"):GetChildren()) do
			if s:IsA("Sound") then
				table.insert(sounds, s) -- Adds sound to preload list
			end
		end

		if #sounds > 0 then
			ContentProvider:PreloadAsync(sounds) -- Preloads sounds
		end

		SoundsPreloaded = true -- Marks sounds as loaded
	end
end

task.spawn(preloadAssets) -- Preloads assets without blocking

local function getViewModel()
	local ViewModel = workspace.CurrentCamera:WaitForChild("ViewModel", 3) -- Gets the viewmodel
	local Humanoid = ViewModel:WaitForChild("Humanoid", 3) -- Gets the humanoid
	return ViewModel, Humanoid -- Returns both
end

-- Using the getViewModel function because although in this script it seems useless; the viewmodel's name changes. This isn't common practise but it makes sense logically to me in my head so I have this function set
-- due to different naming

local function playAnimation(animName)
	local ViewModel, Humanoid = getViewModel() -- Gets viewmodel and humanoid
	local Animation = ViewModel:WaitForChild("AnimationFolder"):FindFirstChild(animName) -- Finds animation

	if Humanoid and Animation then
		if currentAnimTrack then
			currentAnimTrack:Stop() -- Stops previous animation
		end

		currentAnimTrack = Humanoid:LoadAnimation(Animation) -- Loads animation
		currentAnimTrack:Play() -- Plays animation
	end
end

local function playSound(SoundName)
	local ViewModel = workspace.CurrentCamera:WaitForChild("ViewModel", 3) -- Gets viewmodel
	local Sound = ViewModel:WaitForChild("SoundsFolder"):FindFirstChild(SoundName) -- Finds sound

	if Sound then
		Sound:Play() -- Plays sound
	end
end

local function playParticle(FolderName)
	local ViewModel = workspace.CurrentCamera:WaitForChild("ViewModel", 3) -- Gets viewmodel
	local ParticleFolder = ViewModel:WaitForChild("Particles"):FindFirstChild(FolderName) -- Finds particles

	if ParticleFolder then
		for _, v in ParticleFolder:GetDescendants() do
			if v:IsA("ParticleEmitter") then
				local EmitTimes = v:GetAttribute("Emit") or 1 -- Gets emit count
				v:Emit(EmitTimes) -- Emits particles
			end
		end
	end
end

local function playBarAnimation()
	Bar.Size = UDim2.new(0, 0, 1, 0) -- Resets bar size
	Bar.Parent.Visible = true -- Shows cooldown bar

	InterfaceModule:Tween(Bar, {Size = UDim2.new(1, 0, 1, 0)}, fireCooldown) -- Tweens bar

	task.spawn(function()
		task.wait(fireCooldown) -- Waits for cooldown
		Bar.Parent.Visible = false -- Hides bar
	end)
end

local function SetAmmo(newAmmo)
	ammo = math.clamp(newAmmo, 0, maxAmmo) -- Clamps ammo value
	Bullets.Text = ammo .. "/" .. maxAmmo -- Updates ammo UI
end

local function CanFire()
	return tick() - lastFire >= fireCooldown and state == GunState.Idle -- Checks if gun can fire
end

local function Reload()
	if state == GunState.Reloading or ammo == maxAmmo then return end -- Prevents reload spam

	setState(GunState.Reloading) -- Sets reload state
	Bullets.Text = "Reloading..." -- Updates UI

	playAnimation("Reload") -- Plays reload animation
	playSound("Reload") -- Plays reload sound
	playParticle("Reload") -- Plays reload particles

	task.wait(reloadTime) -- Waits reload duration

	ammo = maxAmmo -- Refills ammo
	Bullets.Text = ammo .. "/" .. maxAmmo -- Updates UI
	setState(GunState.Idle) -- Sets state back to idle
end

local function updateRaycastParams()
	local ignore = {char, workspace.CurrentCamera} -- Stores ignored instances

	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= player and plr.Character then
			for _, part in ipairs(plr.Character:GetChildren()) do
				if part:IsA("BasePart") then
					if part.Name ~= "HeadHitbox" and part.Name ~= "BodyHitbox" and part.Name ~= "Right Arm" then
						table.insert(ignore, part) -- Ignores non-hitbox parts
					end
				elseif part:IsA("Tool") or part:IsA("Accessory") then
					for _, p in ipairs(part:GetDescendants()) do
						if p:IsA("BasePart") then
							table.insert(ignore, p) -- Ignores tool/accessory parts
						end
					end
				end
			end
		end
	end

	if workspace:FindFirstChild("CurrentMap") then
		for _, folder in ipairs(workspace.CurrentMap:GetDescendants()) do
			if folder:IsA("Folder") and (folder.Name == "Boundaries" or folder.Name == "Spawns") then
				for _, part in ipairs(folder:GetDescendants()) do
					if part:IsA("BasePart") then
						table.insert(ignore, part) -- Ignores map boundaries and spawns
					end
				end
			end
		end
	end

	local params = RaycastParams.new() -- Creates raycast params
	params.FilterDescendantsInstances = ignore -- Applies ignore list
	params.FilterType = Enum.RaycastFilterType.Exclude -- Sets exclude mode
	CachedParams = params -- Caches params
end

local function Tracer(Position)
	local ViewModel = workspace.CurrentCamera:FindFirstChild("ViewModel") -- Gets viewmodel
	if not ViewModel then return end -- Stops if missing

	local NewPart = ShootPart:Clone() -- Clones tracer part
	NewPart.Position = Position -- Sets tracer position

	local NewShootParticle = ViewModel.Particles.Shoot.Attachment.Shoot:Clone() -- Clones tracer particles
	NewShootParticle.ZOffset = 2 -- Offsets particles
	NewShootParticle.Parent = NewPart -- Parents particles

	NewPart.Parent = workspace -- Parents tracer
	NewShootParticle:Emit(15) -- Emits particles

	Debris:AddItem(NewPart, 1) -- Cleans up tracer
end

local function Fire()
	if char.HumanoidRootPart:GetAttribute("Planting") then return end -- Prevents firing while planting
	if char.HumanoidRootPart:GetAttribute("Defusing") then return end -- Prevents firing while defusing
	if not CanFire() then return end -- Prevents firing during cooldown

	if ammo <= 0 then
		Reload() -- Reloads if out of ammo
		return
	end

	lastFire = tick() -- Updates last fire time
	ammo -= 1 -- Removes ammo
	Bullets.Text = ammo .. "/" .. maxAmmo -- Updates UI

	local origin = workspace.CurrentCamera.CFrame.Position -- Ray start position
	local direction = (mouse.Hit.Position - origin).Unit * 500 -- Ray direction

	if not CachedParams then updateRaycastParams() end -- Updates raycast params if missing

	local result = workspace:Raycast(origin, direction, CachedParams) -- Performs raycast

	if result then
		ShootEvent:FireServer(result.Instance, result.Position) -- Sends hit to server
		Tracer(result.Position) -- Plays tracer
	end

	setState(GunState.Firing) -- Sets firing state
	playAnimation("Shoot") -- Plays shoot animation
	playSound("Shoot") -- Plays shoot sound
	playParticle("Shoot") -- Plays shoot particles
	playBarAnimation() -- Plays cooldown bar

	task.delay(fireCooldown, function()
		if state == GunState.Firing then
			setState(GunState.Idle) -- Resets to idle
		end
	end)
end

local function EquipGun()
	player.CameraMode = Enum.CameraMode.LockFirstPerson -- Locks camera to first person

	if char.HumanoidRootPart:GetAttribute("Defusing") then return end -- Prevents equip while defusing

	CharHumanoid.WalkSpeed = 20 -- Resets walk speed

	local currentTool = char:FindFirstChildOfClass("Tool") -- Gets equipped tool
	if currentTool and currentTool ~= Tool then
		currentTool.Parent = player.Backpack -- Unequips other tool
	end

	if not Equipped then
		Equipped = true -- Marks as equipped
		char.Humanoid:EquipTool(Tool) -- Equips gun
		playAnimation("Equip") -- Plays equip animation
		playSound("Equip") -- Plays equip sound
	end
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end -- Ignores UI input

	if input.KeyCode == Enum.KeyCode.R then
		Reload() -- Reload key
	elseif input.KeyCode == Enum.KeyCode.One then
		EquipGun() -- Equip key
	elseif input.KeyCode == Enum.KeyCode.Y or input.KeyCode == Enum.KeyCode.F then
		if not Equipped then return end -- Prevents inspect when unequipped
		playAnimation("Inspect") -- Plays inspect animation
	end
end)

Tool.Activated:Connect(Fire) -- Fires gun on click

Tool.Equipped:Connect(function()
	EquipGun() -- Equips gun
	GunFrame.Visible = true -- Shows UI
	Bullets.Text = ammo .. "/" .. maxAmmo -- Updates ammo UI
	updateRaycastParams() -- Updates raycast params
end)

Tool.Unequipped:Connect(function()
	GunFrame.Visible = false -- Hides UI
	Equipped = false -- Marks unequipped
	CachedParams = nil -- Clears cached params

	if currentAnimTrack then
		currentAnimTrack:Stop() -- Stops animation
		currentAnimTrack = nil -- Clears animation reference
	end
end)

IndicatorEvent.OnClientEvent:Connect(function(Position, Damage, isHeadShot)
	local NewIndicator = IndicatorPart:Clone() -- Clones indicator
	local Label = NewIndicator.BillboardGui.TextLabel -- Gets text label

	Label.Text = Damage -- Sets damage text
	HitSound:Play() -- Plays hit sound

	if isHeadShot then
		Label.TextColor3 = Color3.new(1, 0, 0) -- Sets red color for headshot
	end

	NewIndicator.Position = Position -- Sets indicator position
	NewIndicator.Parent = workspace -- Parents indicator

	local tweenInfo = TweenInfo.new(1.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out) -- Tween settings
	local tween = TweenService:Create(NewIndicator, tweenInfo, {
		Position = NewIndicator.Position + Vector3.new(0, 5, 0) -- Moves indicator upward
	})

	tween:Play() -- Plays tween
	Debris:AddItem(NewIndicator, 1.5) -- Cleans up indicator
end)
