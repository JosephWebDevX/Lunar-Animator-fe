--!nocheck
-- ══════════════════════════════════════════════════════════════════════
--  LUNAR ANIMATOR • Recriação do Moon Animator em LocalScript
--  UI: Rayfield + Timeline visual própria
--  Ferramentas: Rig, Keyframes, Pose, Cutscene/Câmera,
--  Efeitos, Exportação e Configurações
-- ══════════════════════════════════════════════════════════════════════

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")
local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local Camera = workspace.CurrentCamera
local Mouse = LocalPlayer:GetMouse()

-- ───────────────────────────── Rayfield ─────────────────────────────

if typeof(loadstring) ~= "function" then
	warn("[Lunar Animator] loadstring indisponível neste ambiente.")
	return
end

local okRF, Rayfield = pcall(function()
	local source = game:HttpGet("https://sirius.menu/rayfield")

	if type(source) ~= "string" or #source < 100 then
		error("O conteúdo do Rayfield não foi recebido corretamente.")
	end

	local loader = loadstring(source)

	if typeof(loader) ~= "function" then
		error("loadstring não retornou uma função.")
	end

	return loader()
end)

if not okRF then
	warn("[Lunar Animator] Falha ao carregar o Rayfield:", tostring(Rayfield))
	return
end

if type(Rayfield) ~= "table" then
	warn("[Lunar Animator] Rayfield retornou um tipo inválido:", typeof(Rayfield))
	return
end

-- ───────────────────────────── Constantes ───────────────────────────

local EASING_STYLES = {
	"Linear",
	"Sine",
	"Quad",
	"Cubic",
	"Quart",
	"Quint",
	"Exponential",
	"Circular",
	"Back",
	"Bounce",
	"Elastic"
}

local EASING_DIRS = {
	"In",
	"Out",
	"InOut"
}

local PRIORITIES = {
	"Core",
	"Idle",
	"Movement",
	"Action",
	"Action2",
	"Action3",
	"Action4"
}

local THEMES = {
	"Default",
	"AmberGlow",
	"Amethyst",
	"Bloom",
	"DarkBlue",
	"Green",
	"Light",
	"Ocean",
	"Serenity"
}

local FPS_OPTIONS = {
	"24",
	"30",
	"60"
}

-- ───────────────────────────── Estado ───────────────────────────────

local State = {
	Rig = nil,

	Motors = {},
	MotorKeys = {},
	KeyToMotor = {},

	SelectedKey = nil,

	Pose = {},
	Clipboard = nil,

	Anim = {
		Name = "LunarAnimation",
		Length = 5,
		FPS = 30,
		Loop = false,
		Speed = 1,
		Priority = "Action",

		Keyframes = {}
	},

	Easing = {
		Style = "Sine",
		Direction = "InOut"
	},

	AutoKey = false,
	ApplyPose = true,

	Time = 0,
	Playing = false,

	CameraKeys = {},
	CutsceneActive = false,
	CameraPreview = false,
	FreeCam = false,

	FreeCamSpeed = 40,

	CamYaw = 0,
	CamPitch = 0,

	Shake = 0,

	HideUIInCutscene = false,

	Settings = {
		Scale = 1,
		Theme = "Default",

		GradientEnabled = true,

		GradA = Color3.fromRGB(28, 36, 74),
		GradB = Color3.fromRGB(44, 150, 170),

		GradRotation = 35,
		AnimatedGradient = true,

		TimelineVisible = true,
		TimelineWidth = 820,
		TimelineOpacity = 0.35
	},

	MainOrigColor = nil,
	LastTrack = nil,
	ClickSelect = false
}

-- ───────────────────────────── Forward declarations ─────────────────

local setTime
local togglePlay
local stopPlayback
local commitKeyframe

local refreshTimeline
local refreshKeyframeUI
local syncJointSliders
local refreshCameraUI
local refreshJointUI

local applyVisuals
local stopCutscene

-- ───────────────────────────── Utilidades ───────────────────────────

local function notify(title, content, duration)
	pcall(function()
		Rayfield:Notify({
			Title = title,
			Content = content,
			Duration = duration or 4,
			Image = "moon"
		})
	end)
end

local function first(o)
	if typeof(o) == "table" then
		return o[1]
	end

	return o
end

local function fmt(n)
	return string.format("%.2f", n)
end

local function snapTime(t)
	local fps = State.Anim.FPS

	return math.clamp(
		math.round(t * fps) / fps,
		0,
		State.Anim.Length
	)
end

local function ease(alpha, style, dir)
	local ok, value = pcall(function()
		return TweenService:GetValue(
			alpha,
			Enum.EasingStyle[style],
			Enum.EasingDirection[dir]
		)
	end)

	return ok and value or alpha
end

local function sample(list, t, getValue, lerp)
	if #list == 0 then
		return nil
	end

	if t <= list[1].Time then
		return getValue(list[1])
	end

	if t >= list[#list].Time then
		return getValue(list[#list])
	end

	for i = 1, #list - 1 do
		local a = list[i]
		local b = list[i + 1]

		if t >= a.Time and t <= b.Time then
			local span = b.Time - a.Time

			local alpha =
				span > 0
				and (t - a.Time) / span
				or 1

			alpha = ease(
				alpha,
				b.Style or "Linear",
				b.Direction or "Out"
			)

			return lerp(
				getValue(a),
				getValue(b),
				alpha
			)
		end
	end

	return getValue(list[#list])
end

local function copyToClipboard(text)
	local fn = setclipboard or toclipboard

	if fn then
		local ok = pcall(fn, text)
		return ok
	end

	return false
end

local function cfToTable(cf)
	return {
		cf:GetComponents()
	}
end

local function tableToCf(t)
	if type(t) ~= "table" then
		return CFrame.new()
	end

	return CFrame.new(table.unpack(t))
end

-- ───────────────────────────── Rig ──────────────────────────────────

local function scanMotors(model)
	local motors = {}
	local keys = {}
	local counts = {}

	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Motor6D") and d.Part0 and d.Part1 then
			table.insert(motors, d)
		end
	end

	table.sort(motors, function(a, b)
		return a.Part1.Name < b.Part1.Name
	end)

	for _, m in ipairs(motors) do
		local base = m.Part1.Name

		counts[base] = (counts[base] or 0) + 1

		if counts[base] > 1 then
			keys[m] = base .. "#" .. counts[base]
		else
			keys[m] = base
		end
	end

	return motors, keys
end

local function getAnimator(model)
	local host =
		model:FindFirstChildOfClass("Humanoid")
		or model:FindFirstChildOfClass("AnimationController")

	if not host then
		return nil, nil
	end

	return host:FindFirstChildOfClass("Animator"), host
end

local function setRig(model)
	if not model or not model:IsA("Model") then
		return
	end

	if State.Rig then
		for _, m in ipairs(State.Motors) do
			pcall(function()
				m.Transform = CFrame.new()
			end)
		end
	end

	State.Rig = model

	State.Motors, State.MotorKeys = scanMotors(model)

	State.KeyToMotor = {}
	State.Pose = {}

	for m, k in pairs(State.MotorKeys) do
		State.KeyToMotor[k] = m
		State.Pose[k] = CFrame.new()
	end

	State.SelectedKey =
		State.Motors[1]
		and State.MotorKeys[State.Motors[1]]
		or nil

	local animator = getAnimator(model)

	if animator then
		for _, track in ipairs(
			animator:GetPlayingAnimationTracks()
		) do
			pcall(function()
				track:Stop(0)
			end)
		end
	end

	local animate = model:FindFirstChild("Animate")

	if animate and animate:IsA("LocalScript") then
		pcall(function()
			animate.Disabled = true
		end)
	end

	refreshJointUI()
	refreshKeyframeUI()
	refreshTimeline()

	notify(
		"Rig selecionado",
		model.Name .. " • " .. #State.Motors .. " juntas encontradas"
	)
end

local function findRigModels()
	local list = {}
	local map = {}

	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("Model")
			and (
				d:FindFirstChildOfClass("Humanoid")
				or d:FindFirstChildWhichIsA("Motor6D", true)
			)
		then
			local name = d.Name

			if map[name] then
				name = name .. " (" .. tostring(#list + 1) .. ")"
			end

			map[name] = d

			table.insert(list, name)
		end

		if #list >= 60 then
			break
		end
	end

	table.sort(list)

	return list, map
end

local function modelFromPart(part)
	local current = part

	while current and current ~= workspace do
		if current:IsA("Model")
			and current:FindFirstChildWhichIsA("Motor6D", true)
		then
			return current
		end

		current = current.Parent
	end

	return nil
end

-- ───────────────────────────── Keyframes ────────────────────────────

local function sortKeys()
	table.sort(
		State.Anim.Keyframes,
		function(a, b)
			return a.Time < b.Time
		end
	)
end

local function findKeyframe(t)
	local tolerance = 0.5 / State.Anim.FPS

	for i, k in ipairs(State.Anim.Keyframes) do
		if math.abs(k.Time - t) < tolerance then
			return k, i
		end
	end

	return nil
end

local function samplePose(t)
	local list = State.Anim.Keyframes
	local result = {}

	for _, key in pairs(State.MotorKeys) do
		result[key] =
			sample(
				list,
				t,

				function(k)
					return k.Poses[key] or CFrame.new()
				end,

				function(a, b, alpha)
					return a:Lerp(b, alpha)
				end
			)
			or CFrame.new()
	end

	return result
end

commitKeyframe = function()
	if not State.Rig then
		notify(
			"Sem rig",
			"Selecione um rig primeiro."
		)

		return
	end

	local t = snapTime(State.Time)
	local kf = findKeyframe(t)

	if not kf then
		kf = {
			Time = t,
			Poses = {},
			Style = State.Easing.Style,
			Direction = State.Easing.Direction
		}

		table.insert(
			State.Anim.Keyframes,
			kf
		)
	end

	kf.Poses = {}

	for k, cf in pairs(State.Pose) do
		kf.Poses[k] = cf
	end

	kf.Style = State.Easing.Style
	kf.Direction = State.Easing.Direction

	sortKeys()

	refreshKeyframeUI()
	refreshTimeline()
end

local function deleteKeyframeAtTime()
	local kf, index =
		findKeyframe(
			snapTime(State.Time)
		)

	if kf then
		table.remove(
			State.Anim.Keyframes,
			index
		)

		refreshKeyframeUI()
		refreshTimeline()

		notify(
			"Keyframe removido",
			fmt(kf.Time) .. "s"
		)
	else
		notify(
			"Nada aqui",
			"Não há keyframe no tempo atual."
		)
	end
end

local function jumpKeyframe(direction)
	local list = State.Anim.Keyframes

	if #list == 0 then
		return
	end

	local target

	if direction > 0 then
		for _, k in ipairs(list) do
			if k.Time > State.Time + 0.0001 then
				target = k
				break
			end
		end
	else
		for i = #list, 1, -1 do
			if list[i].Time < State.Time - 0.0001 then
				target = list[i]
				break
			end
		end
	end

	if target then
		setTime(target.Time)
	end
end

setTime = function(t)
	State.Time = math.clamp(
		t,
		0,
		State.Anim.Length
	)

	if not State.Playing
		and #State.Anim.Keyframes > 0
	then
		State.Pose =
			samplePose(State.Time)

		syncJointSliders()
	end

	refreshTimeline(true)
end

togglePlay = function()
	if State.Time >= State.Anim.Length
		and not State.Anim.Loop
	then
		State.Time = 0
	end

	State.Playing = not State.Playing

	refreshTimeline(true)
end

stopPlayback = function()
	State.Playing = false

	setTime(0)

	if State.CutsceneActive then
		stopCutscene()
	end
end

-- ───────────────────────────── Pose ─────────────────────────────────

local function poseFromValues(
	px,
	py,
	pz,
	rx,
	ry,
	rz
)
	return CFrame.new(px, py, pz)
		* CFrame.fromEulerAnglesXYZ(
			math.rad(rx),
			math.rad(ry),
			math.rad(rz)
		)
end

local function valuesFromPose(cf)
	local rx, ry, rz =
		cf:ToEulerAnglesXYZ()

	return
		cf.X,
		cf.Y,
		cf.Z,
		math.deg(rx),
		math.deg(ry),
		math.deg(rz)
end

-- ───────────────────────────── Câmera ───────────────────────────────

local function sortCam()
	table.sort(
		State.CameraKeys,
		function(a, b)
			return a.Time < b.Time
		end
	)
end

local function findCamKey(t)
	local tolerance = 0.5 / State.Anim.FPS

	for i, k in ipairs(State.CameraKeys) do
		if math.abs(k.Time - t) < tolerance then
			return k, i
		end
	end

	return nil
end

local function sampleCamera(t)
	local cf =
		sample(
			State.CameraKeys,
			t,
			function(k)
				return k.CFrame
			end,
			function(a, b, alpha)
				return a:Lerp(b, alpha)
			end
		)

	local fov =
		sample(
			State.CameraKeys,
			t,
			function(k)
				return k.FOV
			end,
			function(a, b, alpha)
				return a + (b - a) * alpha
			end
		)

	return cf, fov
end

local function addCameraKey()
	local t = snapTime(State.Time)
	local k = findCamKey(t)

	if not k then
		k = {
			Time = t
		}

		table.insert(
			State.CameraKeys,
			k
		)
	end

	k.CFrame = workspace.CurrentCamera.CFrame
	k.FOV = workspace.CurrentCamera.FieldOfView
	k.Style = State.Easing.Style
	k.Direction = State.Easing.Direction

	sortCam()

	refreshCameraUI()
	refreshTimeline()

	notify(
		"Keyframe de câmera",
		"Salvo em " .. fmt(t) .. "s"
	)
end

local function setFreeCam(on)
	State.FreeCam = on

	local currentCamera = workspace.CurrentCamera

	if on then
		local x, y =
			currentCamera.CFrame:ToEulerAnglesYXZ()

		State.CamPitch = x
		State.CamYaw = y

		currentCamera.CameraType =
			Enum.CameraType.Scriptable
	else
		UserInputService.MouseBehavior =
			Enum.MouseBehavior.Default

		if not State.CutsceneActive then
			currentCamera.CameraType =
				Enum.CameraType.Custom
		end
	end
end

local function updateFreeCam(dt)
	local currentCamera =
		workspace.CurrentCamera

	local speed =
		State.FreeCamSpeed
		* (
			UserInputService:IsKeyDown(
				Enum.KeyCode.LeftShift
			)
			and 3
			or 1
		)

	local cf = currentCamera.CFrame
	local move = Vector3.zero

	if UserInputService:IsKeyDown(Enum.KeyCode.W) then
		move += cf.LookVector
	end

	if UserInputService:IsKeyDown(Enum.KeyCode.S) then
		move -= cf.LookVector
	end

	if UserInputService:IsKeyDown(Enum.KeyCode.D) then
		move += cf.RightVector
	end

	if UserInputService:IsKeyDown(Enum.KeyCode.A) then
		move -= cf.RightVector
	end

	if UserInputService:IsKeyDown(Enum.KeyCode.E) then
		move += Vector3.yAxis
	end

	if UserInputService:IsKeyDown(Enum.KeyCode.Q) then
		move -= Vector3.yAxis
	end

	local pos = cf.Position

	if move.Magnitude > 0 then
		pos +=
			move.Unit
			* speed
			* dt
	end

	if UserInputService:IsMouseButtonPressed(
		Enum.UserInputType.MouseButton2
	) then

		UserInputService.MouseBehavior =
			Enum.MouseBehavior.LockCurrentPosition

		local delta =
			UserInputService:GetMouseDelta()

		State.CamYaw -=
			delta.X * 0.0035

		State.CamPitch =
			math.clamp(
				State.CamPitch
					- delta.Y * 0.0035,
				-1.55,
				1.55
			)
	else
		UserInputService.MouseBehavior =
			Enum.MouseBehavior.Default
	end

	currentCamera.CFrame =
		CFrame.new(pos)
		* CFrame.fromEulerAnglesYXZ(
			State.CamPitch,
			State.CamYaw,
			0
		)
end

-- ───────────────────────────── FX ───────────────────────────────────

local FX = {}

do
	local gui = Instance.new("ScreenGui")

	gui.Name = "LunarFX"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 2000

	gui.Parent = PlayerGui

	local function bar(anchorY)
		local f = Instance.new("Frame")

		f.AnchorPoint =
			Vector2.new(0.5, anchorY)

		f.Position =
			UDim2.new(
				0.5,
				0,
				anchorY,
				0
			)

		f.Size =
			UDim2.new(
				1,
				0,
				0,
				0
			)

		f.BackgroundColor3 =
			Color3.new(0, 0, 0)

		f.BorderSizePixel = 0
		f.Parent = gui

		return f
	end

	FX.Top = bar(0)
	FX.Bottom = bar(1)

	FX.Fade = Instance.new("Frame")

	FX.Fade.Size =
		UDim2.fromScale(1, 1)

	FX.Fade.BackgroundColor3 =
		Color3.new(0, 0, 0)

	FX.Fade.BackgroundTransparency = 1
	FX.Fade.BorderSizePixel = 0
	FX.Fade.Parent = gui

	FX.LetterboxSize = 0.12
	FX.FadeDuration = 1
end

local function setLetterbox(on)
	local h =
		on
		and FX.LetterboxSize
		or 0

	local info =
		TweenInfo.new(
			0.6,
			Enum.EasingStyle.Quart,
			Enum.EasingDirection.Out
		)

	TweenService:Create(
		FX.Top,
		info,
		{
			Size = UDim2.new(
				1,
				0,
				h,
				0
			)
		}
	):Play()

	TweenService:Create(
		FX.Bottom,
		info,
		{
			Size = UDim2.new(
				1,
				0,
				h,
				0
			)
		}
	):Play()
end

local function fade(toBlack)
	local info =
		TweenInfo.new(
			FX.FadeDuration,
			Enum.EasingStyle.Sine,
			Enum.EasingDirection.InOut
		)

	TweenService:Create(
		FX.Fade,
		info,
		{
			BackgroundTransparency =
				toBlack and 0 or 1
		}
	):Play()
end

local function getLightingEffect(class, name)
	local e = Lighting:FindFirstChild(name)

	if not e then
		e = Instance.new(class)
		e.Name = name
		e.Parent = Lighting
	end

	return e
end

local function playCutscene()
	if #State.CameraKeys == 0 then
		notify(
			"Sem câmera",
			"Adicione keyframes de câmera primeiro."
		)

		return
	end

	State.CutsceneActive = true

	setFreeCam(false)

	local currentCamera =
		workspace.CurrentCamera

	currentCamera.CameraType =
		Enum.CameraType.Scriptable

	State.Time = 0
	State.Playing = true

	if State.HideUIInCutscene then
		pcall(function()
			Rayfield:Destroy()
		end)
	end
end

stopCutscene = function()
	State.CutsceneActive = false

	local currentCamera =
		workspace.CurrentCamera

	if not State.FreeCam then
		currentCamera.CameraType =
			Enum.CameraType.Custom

		currentCamera.FieldOfView = 70
	end
end

local function generateOrbit(
	radius,
	height,
	count
)
	if not State.Rig then
		notify(
			"Sem rig",
			"Selecione um rig para orbitar."
		)

		return
	end

	local root =
		State.Rig.PrimaryPart
		or State.Rig:FindFirstChild(
			"HumanoidRootPart"
		)
		or State.Rig:FindFirstChildWhichIsA(
			"BasePart"
		)

	if not root then
		return
	end

	State.CameraKeys = {}

	local center = root.Position

	for i = 0, count do
		local angle =
			(i / count)
			* math.pi
			* 2

		local pos =
			center
			+ Vector3.new(
				math.cos(angle) * radius,
				height,
				math.sin(angle) * radius
			)

		table.insert(
			State.CameraKeys,
			{
				Time =
					(i / count)
					* State.Anim.Length,

				CFrame =
					CFrame.lookAt(
						pos,
						center
					),

				FOV = 60,

				Style = "Linear",
				Direction = "Out"
			}
		)
	end

	refreshCameraUI()
	refreshTimeline()

	notify(
		"Órbita gerada",
		(count + 1)
			.. " keyframes de câmera"
	)
end

local function generateDolly(
	startDist,
	endDist,
	height
)
	if not State.Rig then
		notify(
			"Sem rig",
			"Selecione um rig."
		)

		return
	end

	local root =
		State.Rig.PrimaryPart
		or State.Rig:FindFirstChild(
			"HumanoidRootPart"
		)
		or State.Rig:FindFirstChildWhichIsA(
			"BasePart"
		)

	if not root then
		return
	end

	local center = root.Position
	local look = root.CFrame.LookVector

	State.CameraKeys = {
		{
			Time = 0,

			CFrame =
				CFrame.lookAt(
					center
						+ look * startDist
						+ Vector3.new(
							0,
							height,
							0
						),
					center
				),

			FOV = 70,

			Style = "Sine",
			Direction = "InOut"
		},

		{
			Time = State.Anim.Length,

			CFrame =
				CFrame.lookAt(
					center
						+ look * endDist
						+ Vector3.new(
							0,
							height,
							0
						),
					center
				),

			FOV = 45,

			Style = "Sine",
			Direction = "InOut"
		}
	}

	refreshCameraUI()
	refreshTimeline()

	notify(
		"Dolly gerado",
		"2 keyframes de câmera"
	)
end

local function focusOnRig()
	if not State.Rig then
		return
	end

	local root =
		State.Rig.PrimaryPart
		or State.Rig:FindFirstChild(
			"HumanoidRootPart"
		)
		or State.Rig:FindFirstChildWhichIsA(
			"BasePart"
		)

	if not root then
		return
	end

	local currentCamera =
		workspace.CurrentCamera

	if not State.FreeCam
		and not State.CutsceneActive
	then
		currentCamera.CameraType =
			Enum.CameraType.Scriptable
	end

	currentCamera.CFrame =
		CFrame.lookAt(
			currentCamera.CFrame.Position,
			root.Position
		)

	local x, y =
		currentCamera.CFrame:ToEulerAnglesYXZ()

	State.CamPitch = x
	State.CamYaw = y
end

-- ───────────────────────────── Exportação ───────────────────────────

local POSE_STYLE_MAP = {
	Linear = "Linear",
	Cubic = "Cubic",
	Elastic = "Elastic",
	Bounce = "Bounce"
}

local function buildKeyframeSequence()
	local ks =
		Instance.new("KeyframeSequence")

	ks.Name = State.Anim.Name
	ks.Loop = State.Anim.Loop

	pcall(function()
		ks.Priority =
			Enum.AnimationPriority[
				State.Anim.Priority
			]
	end)

	local rig = State.Rig

	if not rig then
		return ks
	end

	local rootPart =
		rig.PrimaryPart
		or rig:FindFirstChild(
			"HumanoidRootPart"
		)

	if not rootPart then
		for _, m in ipairs(State.Motors) do
			local isChild = false

			for _, m2 in ipairs(State.Motors) do
				if m2.Part1 == m.Part0 then
					isChild = true
					break
				end
			end

			if not isChild then
				rootPart = m.Part0
				break
			end
		end
	end

	for _, kf in ipairs(State.Anim.Keyframes) do
		local key =
			Instance.new("Keyframe")

		key.Time = kf.Time
		key.Parent = ks

		local poses = {}

		local function getPose(part)
			if poses[part] then
				return poses[part]
			end

			local p =
				Instance.new("Pose")

			p.Name = part.Name
			p.Weight = 1

			pcall(function()
				p.EasingStyle =
					Enum.PoseEasingStyle[
						POSE_STYLE_MAP[
							kf.Style
						] or "Cubic"
					]

				p.EasingDirection =
					Enum.PoseEasingDirection[
						kf.Direction or "Out"
					]
			end)

			poses[part] = p

			return p
		end

		if rootPart then
			local rootPose =
				getPose(rootPart)

			rootPose.CFrame =
				CFrame.new()

			rootPose.Parent = key

			for _, m in ipairs(State.Motors) do
				local p1 =
					getPose(m.Part1)

				p1.CFrame =
					kf.Poses[
						State.MotorKeys[m]
					]
					or CFrame.new()

				p1.Parent =
					getPose(m.Part0)
			end

			for _, p in pairs(poses) do
				if not p.Parent then
					p.Parent = rootPose
				end
			end
		end
	end

	return ks
end

local function serializeProject()
	local data = {
		Name = State.Anim.Name,
		Length = State.Anim.Length,
		FPS = State.Anim.FPS,
		Loop = State.Anim.Loop,
		Priority = State.Anim.Priority,

		RigName =
			State.Rig
			and State.Rig.Name
			or nil,

		Keyframes = {},
		CameraKeys = {}
	}

	for _, k in ipairs(State.Anim.Keyframes) do
		local poses = {}

		for name, cf in pairs(k.Poses) do
			poses[name] =
				cfToTable(cf)
		end

		table.insert(
			data.Keyframes,
			{
				Time = k.Time,
				Style = k.Style,
				Direction = k.Direction,
				Poses = poses
			}
		)
	end

	for _, c in ipairs(State.CameraKeys) do
		table.insert(
			data.CameraKeys,
			{
				Time = c.Time,
				FOV = c.FOV,
				Style = c.Style,
				Direction = c.Direction,
				CFrame = cfToTable(c.CFrame)
			}
		)
	end

	return HttpService:JSONEncode(data)
end

local function importProject(json)
	local ok, data =
		pcall(function()
			return HttpService:JSONDecode(json)
		end)

	if not ok
		or type(data) ~= "table"
	then
		notify(
			"Erro",
			"JSON inválido."
		)

		return
	end

	State.Anim.Name =
		data.Name
		or State.Anim.Name

	State.Anim.Length =
		data.Length
		or State.Anim.Length

	State.Anim.FPS =
		data.FPS
		or State.Anim.FPS

	if data.Loop ~= nil then
		State.Anim.Loop = data.Loop
	end

	State.Anim.Priority =
		data.Priority
		or "Action"

	State.Anim.Keyframes = {}

	for _, k in ipairs(
		data.Keyframes or {}
	) do
		local poses = {}

		for name, t in pairs(
			k.Poses or {}
		) do
			poses[name] =
				tableToCf(t)
		end

		table.insert(
			State.Anim.Keyframes,
			{
				Time = k.Time,
				Style = k.Style or "Linear",
				Direction =
					k.Direction or "Out",
				Poses = poses
			}
		)
	end

	State.CameraKeys = {}

	for _, c in ipairs(
		data.CameraKeys or {}
	) do
		table.insert(
			State.CameraKeys,
			{
				Time = c.Time,
				FOV = c.FOV or 70,
				Style =
					c.Style or "Linear",
				Direction =
					c.Direction or "Out",
				CFrame =
					tableToCf(c.CFrame)
			}
		)
	end

	sortKeys()
	sortCam()

	refreshKeyframeUI()
	refreshCameraUI()
	refreshTimeline()

	notify(
		"Projeto importado",
		#State.Anim.Keyframes
			.. " keyframes • "
			.. #State.CameraKeys
			.. " câmeras"
	)
end

local function exportLuaCode()
	local L = {}

	local function add(s)
		table.insert(L, s)
	end

	add(
		"-- Lunar Animator • Cole na Command Bar do Studio para criar a KeyframeSequence em ServerStorage"
	)

	add(
		"local ks = Instance.new('KeyframeSequence')"
	)

	add(
		("ks.Name = %q"):format(
			State.Anim.Name
		)
	)

	add(
		("ks.Loop = %s"):format(
			tostring(State.Anim.Loop)
		)
	)

	add(
		("ks.Priority = Enum.AnimationPriority.%s")
			:format(State.Anim.Priority)
	)

	add(
		"local function pose(name, parent, cf, style, dir) local p = Instance.new('Pose') p.Name = name p.Weight = 1 p.CFrame = cf p.EasingStyle = Enum.PoseEasingStyle[style] p.EasingDirection = Enum.PoseEasingDirection[dir] p.Parent = parent return p end"
	)

	local rootPart =
		State.Rig
		and (
			State.Rig.PrimaryPart
			or State.Rig:FindFirstChild(
				"HumanoidRootPart"
			)
		)

	local rootName =
		rootPart
		and rootPart.Name
		or "HumanoidRootPart"

	for _, kf in ipairs(
		State.Anim.Keyframes
	) do
		local style =
			POSE_STYLE_MAP[kf.Style]
			or "Cubic"

		add(
			(
				"do local k = Instance.new('Keyframe') k.Time = %.4f k.Parent = ks"
			):format(kf.Time)
		)

		add(
			(
				"  local P = {} P[%q] = pose(%q, k, CFrame.new(), %q, %q)"
			):format(
				rootName,
				rootName,
				style,
				kf.Direction or "Out"
			)
		)

		for _, m in ipairs(
			State.Motors
		) do
			local cf =
				kf.Poses[
					State.MotorKeys[m]
				]
				or CFrame.new()

			local components = {}

			for _, c in ipairs(
				{
					cf:GetComponents()
				}
			) do
				table.insert(
					components,
					string.format(
						"%.5f",
						c
					)
				)
			end

			add(
				(
					"  P[%q] = pose(%q, P[%q] or P[%q], CFrame.new(%s), %q, %q)"
				):format(
					m.Part1.Name,
					m.Part1.Name,
					m.Part0.Name,
					rootName,
					table.concat(
						components,
						","
					),
					style,
					kf.Direction or "Out"
				)
			)
		end

		add("end")
	end

	add(
		"ks.Parent = game:GetService('ServerStorage')"
	)

	add(
		"print('KeyframeSequence criada:', ks:GetFullName())"
	)

	return table.concat(L, "\n")
end

local function playViaAnimator()
	if not State.Rig then
		notify(
			"Sem rig",
			"Selecione um rig."
		)

		return
	end

	if #State.Anim.Keyframes < 1 then
		notify(
			"Sem keyframes",
			"Adicione keyframes primeiro."
		)

		return
	end

	local ks =
		buildKeyframeSequence()

	local ok, err =
		pcall(function()
			local id =
				KeyframeSequenceProvider:RegisterKeyframeSequence(
					ks
				)

			local anim =
				Instance.new("Animation")

			anim.AnimationId = id

			local animator, host =
				getAnimator(State.Rig)

			if not animator then
				if not host then
					error(
						"Rig sem Humanoid/AnimationController"
					)
				end

				animator =
					Instance.new("Animator")

				animator.Parent = host
			end

			if State.LastTrack then
				pcall(function()
					State.LastTrack:Stop()
				end)
			end

			State.ApplyPose = false

			for _, m in ipairs(
				State.Motors
			) do
				m.Transform = CFrame.new()
			end

			local track =
				animator:LoadAnimation(anim)

			track.Looped =
				State.Anim.Loop

			track:Play()

			State.LastTrack = track
		end)

	if ok then
		notify(
			"Tocando via Animator",
			"KeyframeSequence registrada."
		)
	else
		notify(
			"Falhou",
			"RegisterKeyframeSequence só funciona no Studio. "
				.. tostring(err),
			6
		)
	end
end

-- ───────────────────────────── Timeline ─────────────────────────────

local TL = {}

local function mk(class, props, parent)
	local inst =
		Instance.new(class)

	for k, v in pairs(props) do
		inst[k] = v
	end

	inst.Parent = parent

	return inst
end

local function buildTimeline()
	local gui =
		mk(
			"ScreenGui",
			{
				Name = "LunarTimeline",
				ResetOnSpawn = false,
				IgnoreGuiInset = true,
				DisplayOrder = 1500,
				ZIndexBehavior =
					Enum.ZIndexBehavior.Sibling
			},
			PlayerGui
		)

	TL.Gui = gui

	TL.Scale =
		mk(
			"UIScale",
			{},
			gui
		)

	local root =
		mk(
			"Frame",
			{
				Name = "Root",

				AnchorPoint =
					Vector2.new(
						0.5,
						1
					),

				Position =
					UDim2.new(
						0.5,
						0,
						1,
						-18
					),

				Size =
					UDim2.new(
						0,
						State.Settings.TimelineWidth,
						0,
						136
					),

				BackgroundColor3 =
					Color3.new(
						1,
						1,
						1
					),

				BorderSizePixel = 0
			},
			gui
		)

	TL.Root = root

	mk(
		"UICorner",
		{
			CornerRadius =
				UDim.new(
					0,
					16
				)
		},
		root
	)

	mk(
		"UIStroke",
		{
			Color =
				Color3.new(
					1,
					1,
					1
				),

			Transparency = 0.8,
			Thickness = 1
		},
		root
	)

	TL.Grad =
		mk(
			"UIGradient",
			{},
			root
		)

	TL.Overlay =
		mk(
			"Frame",
			{
				Name = "Overlay",
				Size = UDim2.fromScale(
					1,
					1
				),

				BackgroundColor3 =
					Color3.fromRGB(
						8,
						10,
						18
					),

				BackgroundTransparency =
					State.Settings.TimelineOpacity,

				BorderSizePixel = 0
			},
			root
		)

	mk(
		"UICorner",
		{
			CornerRadius =
				UDim.new(
					0,
					16
				)
		},
		TL.Overlay
	)

	-- Header

	local header =
		mk(
			"Frame",
			{
				Name = "Header",

				Size =
					UDim2.new(
						1,
						-28,
						0,
						30
					),

				Position =
					UDim2.new(
						0,
						14,
						0,
						10
					),

				BackgroundTransparency = 1
			},
			root
		)

	TL.Title =
		mk(
			"TextLabel",
			{
				Text = "LUNAR ANIMATOR",

				Font =
					Enum.Font.GothamBlack,

				TextSize = 14,

				TextColor3 =
					Color3.new(
						1,
						1,
						1
					),

				BackgroundTransparency = 1,

				Size =
					UDim2.new(
						0,
						220,
						1,
						0
					),

				TextXAlignment =
					Enum.TextXAlignment.Left
			},
			header
		)

	mk(
		"UIGradient",
		{
			Color =
				ColorSequence.new(
					Color3.new(
						1,
						1,
						1
					),
					Color3.fromRGB(
						170,
						220,
						255
					)
				)
		},
		TL.Title
	)

	TL.TimeLabel =
		mk(
			"TextLabel",
			{
				Text =
					"0.00s / 5.00s • f0",

				Font =
					Enum.Font.Code,

				TextSize = 13,

				TextColor3 =
					Color3.fromRGB(
						225,
						232,
						245
					),

				BackgroundTransparency = 1,

				AnchorPoint =
					Vector2.new(
						1,
						0
					),

				Position =
					UDim2.new(
						1,
						0,
						0,
						0
					),

				Size =
					UDim2.new(
						0,
						240,
						1,
						0
					),

				TextXAlignment =
					Enum.TextXAlignment.Right
			},
			header
		)

	local btnRow =
		mk(
			"Frame",
			{
				Size =
					UDim2.new(
						0,
						230,
						1,
						0
					),

				Position =
					UDim2.new(
						0.5,
						-115,
						0,
						0
					),

				BackgroundTransparency = 1
			},
			header
		)

	mk(
		"UIListLayout",
		{
			FillDirection =
				Enum.FillDirection.Horizontal,

			HorizontalAlignment =
				Enum.HorizontalAlignment.Center,

			VerticalAlignment =
				Enum.VerticalAlignment.Center,

			Padding =
				UDim.new(
					0,
					6
				)
		},
		btnRow
	)

	local function tbtn(
		text,
		cb,
		width
	)
		local b =
			mk(
				"TextButton",
				{
					Text = text,

					Font =
						Enum.Font.GothamBold,

					TextSize = 13,

					TextColor3 =
						Color3.new(
							1,
							1,
							1
						),

					BackgroundColor3 =
						Color3.new(
							1,
							1,
							1
						),

					BackgroundTransparency =
						0.86,

					Size =
						UDim2.new(
							0,
							width or 36,
							0,
							26
						),

					AutoButtonColor = true,
					BorderSizePixel = 0
				},
				btnRow
			)

		mk(
			"UICorner",
			{
				CornerRadius =
					UDim.new(
						0,
						8
					)
			},
			b
		)

		mk(
			"UIStroke",
			{
				Color =
					Color3.new(
						1,
						1,
						1
					),

				Transparency = 0.85
			},
			b
		)

		b.MouseButton1Click:Connect(cb)

		return b
	end

	tbtn("|◀", function()
		setTime(0)
	end)

	tbtn("◁", function()
		jumpKeyframe(-1)
	end)

	TL.PlayBtn =
		tbtn(
			"▶",
			function()
				togglePlay()
			end,
			44
		)

	tbtn("■", function()
		stopPlayback()
	end)

	tbtn("▷", function()
		jumpKeyframe(1)
	end)

	tbtn("◆", function()
		commitKeyframe()
	end)

	-- Ruler

	local ruler =
		mk(
			"Frame",
			{
				Name = "Ruler",

				Position =
					UDim2.new(
						0,
						14,
						0,
						50
					),

				Size =
					UDim2.new(
						1,
						-28,
						0,
						42
					),

				BackgroundColor3 =
					Color3.new(
						0,
						0,
						0
					),

				BackgroundTransparency =
					0.55,

				BorderSizePixel = 0
			},
			root
		)

	mk(
		"UICorner",
		{
			CornerRadius =
				UDim.new(
					0,
					10
				)
		},
		ruler
	)

	TL.Ruler = ruler

	TL.Ticks =
		mk(
			"Frame",
			{
				Name = "Ticks",
				Size =
					UDim2.fromScale(
						1,
						1
					),
				BackgroundTransparency = 1
			},
			ruler
		)

	TL.Markers =
		mk(
			"Frame",
			{
				Name = "Markers",
				Size =
					UDim2.fromScale(
						1,
						1
					),
				BackgroundTransparency = 1,
				ZIndex = 3
			},
			ruler
		)

	-- Camera lane

	local camLane =
		mk(
			"Frame",
			{
				Name = "CamLane",

				Position =
					UDim2.new(
						0,
						14,
						0,
						98
					),

				Size =
					UDim2.new(
						1,
						-28,
						0,
						26
					),

				BackgroundColor3 =
					Color3.new(
						0,
						0,
						0
					),

				BackgroundTransparency =
					0.6,

				BorderSizePixel = 0
			},
			root
		)

	mk(
		"UICorner",
		{
			CornerRadius =
				UDim.new(
					0,
					8
				)
		},
		camLane
	)

	mk(
		"TextLabel",
		{
			Text = "CÂMERA",

			Font =
				Enum.Font.GothamBold,

			TextSize = 9,

			TextColor3 =
				Color3.fromRGB(
					200,
					215,
					240
				),

			TextTransparency = 0.35,

			BackgroundTransparency = 1,

			AnchorPoint =
				Vector2.new(
					1,
					0.5
				),

			Position =
				UDim2.new(
					1,
					-8,
					0.5,
					0
				),

			Size =
				UDim2.new(
					0,
					60,
					1,
					0
				),

			TextXAlignment =
				Enum.TextXAlignment.Right
		},
		camLane
	)

	TL.CamLane = camLane

	TL.CamMarkers =
		mk(
			"Frame",
			{
				Name = "Markers",
				Size =
					UDim2.fromScale(
						1,
						1
					),
				BackgroundTransparency = 1,
				ZIndex = 3
			},
			camLane
		)

	-- Scrubber

	TL.Scrub =
		mk(
			"Frame",
			{
				Name = "Scrub",

				AnchorPoint =
					Vector2.new(
						0.5,
						0
					),

				Position =
					UDim2.new(
						0,
						14,
						0,
						46
					),

				Size =
					UDim2.new(
						0,
						2,
						0,
						82
					),

				BackgroundColor3 =
					Color3.new(
						1,
						1,
						1
					),

				BorderSizePixel = 0,

				ZIndex = 6
			},
			root
		)

	local head =
		mk(
			"Frame",
			{
				AnchorPoint =
					Vector2.new(
						0.5,
						0
					),

				Position =
					UDim2.new(
						0.5,
						0,
						0,
						-5
					),

				Size =
					UDim2.new(
						0,
						10,
						0,
						10
					),

				BackgroundColor3 =
					Color3.new(
						1,
						1,
						1
					),

				BorderSizePixel = 0,
				ZIndex = 7
			},
			TL.Scrub
		)

	mk(
		"UICorner",
		{
			CornerRadius =
				UDim.new(
					1,
					0
				)
		},
		head
	)

	-- Scrubbing

	local dragging = false

	local function scrubFromX(x)
		local alpha =
			math.clamp(
				(
					x
					- ruler.AbsolutePosition.X
				)
					/ math.max(
						ruler.AbsoluteSize.X,
						1
					),
				0,
				1
			)

		setTime(
			alpha
				* State.Anim.Length
		)
	end

	for _, lane in ipairs({
		ruler,
		camLane
	}) do

		lane.InputBegan:Connect(
			function(input)
				if input.UserInputType
						== Enum.UserInputType.MouseButton1
					or input.UserInputType
						== Enum.UserInputType.Touch
				then

					dragging = true

					scrubFromX(
						input.Position.X
					)
				end
			end
		)
	end

	UserInputService.InputChanged:Connect(
		function(input)
			if dragging
				and (
					input.UserInputType
						== Enum.UserInputType.MouseMovement
					or input.UserInputType
						== Enum.UserInputType.Touch
				)
			then

				scrubFromX(
					input.Position.X
				)
			end
		end
	)

	UserInputService.InputEnded:Connect(
		function(input)
			if input.UserInputType
					== Enum.UserInputType.MouseButton1
				or input.UserInputType
					== Enum.UserInputType.Touch
			then

				dragging = false
			end
		end
	)

	-- Arrastar timeline

	do
		local moving = false
		local startPos
		local startInput

		TL.Title.InputBegan:Connect(
			function(input)
				if input.UserInputType
					== Enum.UserInputType.MouseButton1
				then

					moving = true
					startPos = root.Position
					startInput = input.Position
				end
			end
		)

		UserInputService.InputChanged:Connect(
			function(input)
				if moving
					and input.UserInputType
						== Enum.UserInputType.MouseMovement
				then

					local delta =
						input.Position
						- startInput

					root.Position =
						UDim2.new(
							startPos.X.Scale,
							startPos.X.Offset
								+ delta.X,

							startPos.Y.Scale,
							startPos.Y.Offset
								+ delta.Y
						)
				end
			end
		)

		UserInputService.InputEnded:Connect(
			function(input)
				if input.UserInputType
					== Enum.UserInputType.MouseButton1
				then
					moving = false
				end
			end
		)
	end
end

refreshTimeline = function(onlyScrub)
	if not TL.Root then
		return
	end

	local len =
		math.max(
			State.Anim.Length,
			0.01
		)

	local alpha =
		math.clamp(
			State.Time / len,
			0,
			1
		)

	TL.Scrub.Position =
		UDim2.new(
			alpha,
			14 - alpha * 28,
			0,
			46
		)

	TL.TimeLabel.Text =
		string.format(
			"%ss / %ss • f%d",

			fmt(State.Time),
			fmt(len),

			math.floor(
				State.Time
					* State.Anim.FPS
					+ 0.5
			)
		)

	TL.PlayBtn.Text =
		State.Playing
		and "❚❚"
		or "▶"

	if onlyScrub then
		return
	end

	TL.Ticks:ClearAllChildren()
	TL.Markers:ClearAllChildren()
	TL.CamMarkers:ClearAllChildren()

	local step =
		len > 30
		and 5
		or (
			len > 12
			and 2
			or 1
		)

	for s = 0, len, step do
		local a = s / len

		mk(
			"Frame",
			{
				Position =
					UDim2.new(
						a,
						0,
						0,
						0
					),

				Size =
					UDim2.new(
						0,
						1,
						1,
						0
					),

				BackgroundColor3 =
					Color3.new(
						1,
						1,
						1
					),

				BackgroundTransparency = 0.82,
				BorderSizePixel = 0
			},
			TL.Ticks
		)

		mk(
			"TextLabel",
			{
				Text = tostring(s) .. "s",

				Font =
					Enum.Font.Gotham,

				TextSize = 9,

				TextColor3 =
					Color3.new(
						1,
						1,
						1
					),

				TextTransparency = 0.45,

				BackgroundTransparency = 1,

				Position =
					UDim2.new(
						a,
						3,
						0,
						1
					),

				Size =
					UDim2.new(
						0,
						30,
						0,
						10
					),

				TextXAlignment =
					Enum.TextXAlignment.Left
			},
			TL.Ticks
		)
	end

	local current =
		findKeyframe(
			snapTime(State.Time)
		)

	for _, kf in ipairs(
		State.Anim.Keyframes
	) do

		local a =
			kf.Time / len

		local isCurrent =
			kf == current

		local marker =
			mk(
				"TextButton",
				{
					Text = "",
					AutoButtonColor = false,

					AnchorPoint =
						Vector2.new(
							0.5,
							0.5
						),

					Position =
						UDim2.new(
							a,
							0,
							0.62,
							0
						),

					Size =
						isCurrent
						and UDim2.new(
							0,
							14,
							0,
							14
						)
						or UDim2.new(
							0,
							11,
							0,
							11
						),

					Rotation = 45,

					BackgroundColor3 =
						Color3.new(
							1,
							1,
							1
						),

					BorderSizePixel = 0,
					ZIndex = 4
				},
				TL.Markers
			)

		mk(
			"UIGradient",
			{
				Color =
					ColorSequence.new(
						State.Settings.GradB,
						Color3.new(
							1,
							1,
							1
						)
					),

				Rotation = 90
			},
			marker
		)

		mk(
			"UIStroke",
			{
				Color =
					Color3.new(
						1,
						1,
						1
					),

				Transparency =
					isCurrent
					and 0
					or 0.6,

				Thickness =
					isCurrent
					and 2
					or 1
			},
			marker
		)

		marker.MouseButton1Click:Connect(
			function()
				setTime(kf.Time)
			end
		)
	end

	local currentCameraKey =
		findCamKey(
			snapTime(State.Time)
		)

	for _, ck in ipairs(
		State.CameraKeys
	) do

		local a =
			ck.Time / len

		local marker =
			mk(
				"TextButton",
				{
					Text = "",
					AutoButtonColor = false,

					AnchorPoint =
						Vector2.new(
							0.5,
							0.5
						),

					Position =
						UDim2.new(
							a,
							0,
							0.5,
							0
						),

					Size =
						UDim2.new(
							0,
							9,
							0,
							9
						),

					Rotation = 45,

					BackgroundColor3 =
						Color3.fromRGB(
							255,
							205,
							120
						),

					BorderSizePixel = 0,
					ZIndex = 4
				},
				TL.CamMarkers
			)

		mk(
			"UIStroke",
			{
				Color =
					Color3.new(
						1,
						1,
						1
					),

				Transparency =
					ck == currentCameraKey
					and 0
					or 0.7,

				Thickness =
					ck == currentCameraKey
					and 2
					or 1
			},
			marker
		)

		marker.MouseButton1Click:Connect(
			function()
				setTime(ck.Time)
			end
		)
	end
end

-- ───────────────────────────── Janela Rayfield ──────────────────────

local Window = Rayfield:CreateWindow({
	Name = "Lunar Animator",

	Icon = "moon",

	LoadingTitle =
		"Lunar Animator",

	LoadingSubtitle =
		"Recriação do Moon Animator • Animações & Cutscenes",

	Theme = State.Settings.Theme,

	ToggleUIKeybind =
		Enum.KeyCode.RightShift,

	ConfigurationSaving = {
		Enabled = false
	},

	Discord = {
		Enabled = false
	},

	KeySystem = false
})

-- ───────────────────────────── Rayfield GUI ─────────────────────────

local function findRayfieldGui()
	local containers = {}

	if gethui then
		pcall(function()
			table.insert(
				containers,
				gethui()
			)
		end)
	end

	pcall(function()
		table.insert(
			containers,
			game:GetService("CoreGui")
		)
	end)

	table.insert(
		containers,
		PlayerGui
	)

	for _, container in ipairs(
		containers
	) do

		local ok, gui =
			pcall(function()
				return container:FindFirstChild(
					"Rayfield"
				)
			end)

		if ok and gui then
			return gui
		end
	end

	return nil
end

applyVisuals = function()
	local S = State.Settings

	local gui =
		findRayfieldGui()

	if gui then
		local main =
			gui:FindFirstChild("Main")

		if main then
			local scale =
				main:FindFirstChild(
					"LunarScale"
				)

			if not scale then
				scale =
					Instance.new(
						"UIScale"
					)

				scale.Name =
					"LunarScale"

				scale.Parent = main
			end

			scale.Scale = S.Scale

			local gradient =
				main:FindFirstChild(
					"LunarGradient"
				)

			if S.GradientEnabled then
				if not gradient then
					gradient =
						Instance.new(
							"UIGradient"
						)

					gradient.Name =
						"LunarGradient"

					gradient.Parent =
						main

					State.MainOrigColor =
						State.MainOrigColor
						or main.BackgroundColor3
				end

				main.BackgroundColor3 =
					Color3.new(
						1,
						1,
						1
					)

				gradient.Color =
					ColorSequence.new(
						S.GradA,
						S.GradB
					)

				gradient.Rotation =
					S.GradRotation

			elseif gradient then
				gradient:Destroy()

				if State.MainOrigColor then
					main.BackgroundColor3 =
						State.MainOrigColor
				end
			end

			local topbar =
				main:FindFirstChild(
					"Topbar"
				)

			if topbar then
				local tg =
					topbar:FindFirstChild(
						"LunarGradient"
					)

				if S.GradientEnabled then
					if not tg then
						tg =
							Instance.new(
								"UIGradient"
							)

						tg.Name =
							"LunarGradient"

						tg.Parent =
							topbar
					end

					tg.Color =
						ColorSequence.new(
							S.GradB,
							S.GradA
						)

					tg.Rotation =
						S.GradRotation

					tg.Transparency =
						NumberSequence.new(
							0.25
						)

				elseif tg then
					tg:Destroy()
				end
			end
		end
	end

	if TL.Root then
		TL.Scale.Scale =
			S.Scale

		TL.Grad.Color =
			ColorSequence.new(
				S.GradA,
				S.GradB
			)

		TL.Grad.Rotation =
			S.GradRotation

		TL.Grad.Enabled =
			S.GradientEnabled

		TL.Root.Visible =
			S.TimelineVisible

		TL.Root.Size =
			UDim2.new(
				0,
				S.TimelineWidth,
				0,
				136
			)

		TL.Overlay.BackgroundTransparency =
			S.TimelineOpacity
	end
end

-- ───────────────────────────── Aba Rig ──────────────────────────────

local TabRig =
	Window:CreateTab(
		"Rig",
		"user"
	)

TabRig:CreateSection(
	"Seleção de Rig"
)

local rigMap = {}

local RigDropdown =
	TabRig:CreateDropdown({
		Name = "Rigs no Workspace",

		Options = {
			"Atualize a lista"
		},

		CurrentOption = {},

		MultipleOptions = false,

		Flag = "RigDropdown",

		Callback = function(opt)
			local name = first(opt)

			if rigMap[name] then
				setRig(
					rigMap[name]
				)
			end
		end
	})

local function refreshRigList()
	local list, map =
		findRigModels()

	rigMap = map

	if #list == 0 then
		list = {
			"Nenhum rig encontrado"
		}
	end

	pcall(function()
		RigDropdown:Refresh(list)
	end)
end

refreshRigList()

TabRig:CreateButton({
	Name =
		"Atualizar lista de rigs",

	Callback =
		refreshRigList
})

TabRig:CreateButton({
	Name =
		"Usar meu personagem",

	Callback = function()
		local character =
			LocalPlayer.Character

		if character then
			setRig(character)
		else
			notify(
				"Sem personagem",
				"Seu personagem não foi encontrado."
			)
		end
	end
})

TabRig:CreateToggle({
	Name =
		"Selecionar rig clicando no mundo",

	CurrentValue = false,

	Flag = "ClickSelect",

	Callback = function(value)
		State.ClickSelect = value
	end
})

Mouse.Button1Down:Connect(
	function()
		if State.ClickSelect
			and Mouse.Target
		then

			local model =
				modelFromPart(
					Mouse.Target
				)

			if model then
				setRig(model)
			end
		end
	end
)

TabRig:CreateSection(
	"Controle do Rig"
)

TabRig:CreateToggle({
	Name =
		"Aplicar pose ao rig (preview ao vivo)",

	CurrentValue = true,

	Flag = "ApplyPose",

	Callback = function(value)
		State.ApplyPose = value

		if not value
			and State.Rig
		then

			for _, m in ipairs(
				State.Motors
			) do

				pcall(function()
					m.Transform =
						CFrame.new()
				end)
			end
		end
	end
})

TabRig:CreateButton({
	Name =
		"Resetar pose (todas as juntas)",

	Callback = function()
		for key in pairs(
			State.Pose
		) do
			State.Pose[key] =
				CFrame.new()
		end

		syncJointSliders()

		if State.AutoKey then
			commitKeyframe()
		end
	end
})

TabRig:CreateButton({
	Name =
		"Capturar pose atual do rig (Transform)",

	Callback = function()
		if not State.Rig then
			return
		end

		for m, key in pairs(
			State.MotorKeys
		) do
			State.Pose[key] =
				m.Transform
		end

		syncJointSliders()

		notify(
			"Pose capturada",
			"Transform atual das juntas copiado para a pose de trabalho."
		)
	end
})

TabRig:CreateButton({
	Name =
		"Parar animação do Animator (se tocando)",

	Callback = function()
		if State.LastTrack then
			pcall(function()
				State.LastTrack:Stop()
			end)
		end

		local animator =
			State.Rig
			and getAnimator(State.Rig)

		if animator then
			for _, track in ipairs(
				animator:GetPlayingAnimationTracks()
			) do

				pcall(function()
					track:Stop(0)
				end)
			end
		end

		State.ApplyPose = true
	end
})

-- ───────────────────────────── Aba Animação ─────────────────────────

local TabAnim =
	Window:CreateTab(
		"Animação",
		"film"
	)

TabAnim:CreateSection(
	"Propriedades"
)

TabAnim:CreateInput({
	Name =
		"Nome da animação",

	PlaceholderText =
		"LunarAnimation",

	RemoveTextAfterFocusLost =
		false,

	Callback = function(text)
		if text ~= "" then
			State.Anim.Name = text
		end
	end
})

TabAnim:CreateSlider({
	Name = "Duração (s)",

	Range = {
		0.5,
		60
	},

	Increment = 0.5,

	Suffix = "s",

	CurrentValue = 5,

	Flag = "Length",

	Callback = function(value)
		State.Anim.Length =
			value

		if State.Time > value then
			State.Time = value
		end

		refreshTimeline()
	end
})

TabAnim:CreateDropdown({
	Name = "FPS",

	Options =
		FPS_OPTIONS,

	CurrentOption = {
		"30"
	},

	MultipleOptions = false,

	Flag = "FPS",

	Callback = function(opt)
		State.Anim.FPS =
			tonumber(
				first(opt)
			)
			or 30

		refreshTimeline(true)
	end
})

TabAnim:CreateSlider({
	Name =
		"Velocidade de reprodução",

	Range = {
		0.1,
		3
	},

	Increment = 0.1,

	Suffix = "x",

	CurrentValue = 1,

	Flag = "Speed",

	Callback = function(value)
		State.Anim.Speed =
			value
	end
})

TabAnim:CreateToggle({
	Name = "Loop",

	CurrentValue = false,

	Flag = "Loop",

	Callback = function(value)
		State.Anim.Loop =
			value
	end
})

TabAnim:CreateDropdown({
	Name = "Prioridade",

	Options =
		PRIORITIES,

	CurrentOption = {
		"Action"
	},

	MultipleOptions = false,

	Flag = "Priority",

	Callback = function(opt)
		State.Anim.Priority =
			first(opt)
	end
})

TabAnim:CreateSection(
	"Easing (para novos keyframes)"
)

TabAnim:CreateDropdown({
	Name = "Estilo",

	Options =
		EASING_STYLES,

	CurrentOption = {
		"Sine"
	},

	MultipleOptions = false,

	Flag = "EaseStyle",

	Callback = function(opt)
		State.Easing.Style =
			first(opt)
	end
})

TabAnim:CreateDropdown({
	Name = "Direção",

	Options =
		EASING_DIRS,

	CurrentOption = {
		"InOut"
	},

	MultipleOptions = false,

	Flag = "EaseDir",

	Callback = function(opt)
		State.Easing.Direction =
			first(opt)
	end
})

TabAnim:CreateButton({
	Name =
		"Aplicar easing ao keyframe atual",

	Callback = function()
		local kf =
			findKeyframe(
				snapTime(
					State.Time
				)
			)

		if kf then
			kf.Style =
				State.Easing.Style

			kf.Direction =
				State.Easing.Direction

			notify(
				"Easing aplicado",
				kf.Style
					.. " / "
					.. kf.Direction
			)
		end
	end
})

TabAnim:CreateButton({
	Name =
		"Aplicar easing a TODOS os keyframes",

	Callback = function()
		for _, kf in ipairs(
			State.Anim.Keyframes
		) do

			kf.Style =
				State.Easing.Style

			kf.Direction =
				State.Easing.Direction
		end

		notify(
			"Easing aplicado",
			"Todos os keyframes atualizados."
		)
	end
})

TabAnim:CreateSection(
	"Reprodução"
)

TabAnim:CreateButton({
	Name = "Play / Pause",

	Callback =
		togglePlay
})

TabAnim:CreateButton({
	Name =
		"Parar (voltar ao início)",

	Callback =
		stopPlayback
})

TabAnim:CreateSlider({
	Name =
		"Posição na timeline",

	Range = {
		0,
		100
	},

	Increment = 1,

	Suffix = "%",

	CurrentValue = 0,

	Flag = "TimePct",

	Callback = function(value)
		setTime(
			(value / 100)
				* State.Anim.Length
		)
	end
})

TabAnim:CreateInput({
	Name =
		"Ir para tempo (s)",

	PlaceholderText =
		"ex: 1.5",

	RemoveTextAfterFocusLost =
		true,

	Callback = function(text)
		local number =
			tonumber(text)

		if number then
			setTime(number)
		end
	end
})

TabAnim:CreateSection(
	"Keyframes"
)

local KeyframeDropdown =
	TabAnim:CreateDropdown({
		Name =
			"Lista de keyframes",

		Options = {
			"Nenhum"
		},

		CurrentOption = {},

		MultipleOptions = false,

		Flag = "KFList",

		Callback = function(opt)
			local text =
				first(opt)

			local time =
				text
				and tonumber(
					text:match(
						"^([%d%.]+)s"
					)
				)

			if time then
				setTime(time)
			end
		end
	})

local KeyframeInfo =
	TabAnim:CreateParagraph({
		Title = "Info",
		Content =
			"Nenhum keyframe."
	})

refreshKeyframeUI = function()
	local options = {}

	for _, kf in ipairs(
		State.Anim.Keyframes
	) do

		table.insert(
			options,
			string.format(
				"%ss • %s/%s",
				fmt(kf.Time),
				kf.Style,
				kf.Direction
			)
		)
	end

	if #options == 0 then
		options = {
			"Nenhum"
		}
	end

	pcall(function()
		KeyframeDropdown:Refresh(
			options
		)
	end)

	pcall(function()
		KeyframeInfo:Set({
			Title =
				State.Anim.Name,

			Content =
				string.format(
					"%d keyframes • %d juntas • %ss @ %dfps • Rig: %s",

					#State.Anim.Keyframes,

					#State.Motors,

					fmt(
						State.Anim.Length
					),

					State.Anim.FPS,

					State.Rig
					and State.Rig.Name
					or "nenhum"
				)
		})
	end)
end

TabAnim:CreateToggle({
	Name =
		"Auto-Key (grava ao mover uma junta)",

	CurrentValue = false,

	Flag = "AutoKey",

	Callback = function(value)
		State.AutoKey = value
	end
})

TabAnim:CreateButton({
	Name =
		"◆ Adicionar / Atualizar keyframe",

	Callback =
		commitKeyframe
})

TabAnim:CreateButton({
	Name =
		"Remover keyframe no tempo atual",

	Callback =
		deleteKeyframeAtTime
})

TabAnim:CreateButton({
	Name =
		"Keyframe anterior",

	Callback = function()
		jumpKeyframe(-1)
	end
})

TabAnim:CreateButton({
	Name =
		"Próximo keyframe",

	Callback = function()
		jumpKeyframe(1)
	end
})

TabAnim:CreateButton({
	Name =
		"Copiar pose",

	Callback = function()
		State.Clipboard = {}

		for key, cf in pairs(
			State.Pose
		) do
			State.Clipboard[key] = cf
		end

		notify(
			"Copiado",
			"Pose atual copiada."
		)
	end
})

TabAnim:CreateButton({
	Name =
		"Colar pose",

	Callback = function()
		if not State.Clipboard then
			return
		end

		for key, cf in pairs(
			State.Clipboard
		) do

			if State.Pose[key] ~= nil then
				State.Pose[key] = cf
			end
		end

		syncJointSliders()

		if State.AutoKey then
			commitKeyframe()
		end
	end
})

TabAnim:CreateInput({
	Name =
		"Duplicar keyframe atual para (s)",

	PlaceholderText =
		"ex: 2.0",

	RemoveTextAfterFocusLost =
		true,

	Callback = function(text)
		local number =
			tonumber(text)

		local kf =
			findKeyframe(
				snapTime(
					State.Time
				)
			)

		if number and kf then
			local time =
				snapTime(number)

			local target =
				findKeyframe(time)

			if not target then
				target = {
					Time = time,
					Poses = {}
				}

				table.insert(
					State.Anim.Keyframes,
					target
				)
			end

			target.Poses = {}

			for key, cf in pairs(
				kf.Poses
			) do
				target.Poses[key] = cf
			end

			target.Style = kf.Style
			target.Direction = kf.Direction

			sortKeys()

			refreshKeyframeUI()
			refreshTimeline()
		end
	end
})

TabAnim:CreateInput({
	Name =
		"Deslocar todos os keyframes (s, pode ser negativo)",

	PlaceholderText =
		"ex: 0.5",

	RemoveTextAfterFocusLost =
		true,

	Callback = function(text)
		local number =
			tonumber(text)

		if not number then
			return
		end

		for _, kf in ipairs(
			State.Anim.Keyframes
		) do

			kf.Time =
				math.clamp(
					kf.Time + number,
					0,
					State.Anim.Length
				)
		end

		sortKeys()

		refreshKeyframeUI()
		refreshTimeline()
	end
})

TabAnim:CreateInput({
	Name =
		"Esticar animação para nova duração (s)",

	PlaceholderText =
		"ex: 8",

	RemoveTextAfterFocusLost =
		true,

	Callback = function(text)
		local number =
			tonumber(text)

		if not number
			or number <= 0
		then
			return
		end

		local last =
			State.Anim.Keyframes[
				#State.Anim.Keyframes
			]

		local oldLength =
			last
			and last.Time > 0
			and last.Time
			or State.Anim.Length

		for _, kf in ipairs(
			State.Anim.Keyframes
		) do
			kf.Time =
				kf.Time
				/ oldLength
				* number
		end

		for _, ck in ipairs(
			State.CameraKeys
		) do
			ck.Time =
				ck.Time
				/ oldLength
				* number
		end

		State.Anim.Length =
			number

		refreshKeyframeUI()
		refreshCameraUI()
		refreshTimeline()
	end
})

TabAnim:CreateButton({
	Name =
		"Inverter animação",

	Callback = function()
		local length =
			State.Anim.Length

		for _, kf in ipairs(
			State.Anim.Keyframes
		) do
			kf.Time =
				length - kf.Time
		end

		sortKeys()

		refreshKeyframeUI()
		refreshTimeline()
	end
})

TabAnim:CreateButton({
	Name =
		"Fazer loop suave (copiar 1º keyframe para o fim)",

	Callback = function()
		local firstKf =
			State.Anim.Keyframes[1]

		if not firstKf then
			return
		end

		local time =
			State.Anim.Length

		local target =
			findKeyframe(time)

		if not target then
			target = {
				Time = time,
				Poses = {}
			}

			table.insert(
				State.Anim.Keyframes,
				target
			)
		end

		target.Poses = {}

		for key, cf in pairs(
			firstKf.Poses
		) do
			target.Poses[key] = cf
		end

		target.Style =
			State.Easing.Style

		target.Direction =
			State.Easing.Direction

		sortKeys()

		refreshKeyframeUI()
		refreshTimeline()
	end
})

TabAnim:CreateButton({
	Name =
		"Limpar TODOS os keyframes",

	Callback = function()
		State.Anim.Keyframes = {}

		refreshKeyframeUI()
		refreshTimeline()

		notify(
			"Limpo",
			"Todos os keyframes foram removidos."
		)
	end
})

-- ───────────────────────────── Aba Pose ────────────────────────────

local TabPose =
	Window:CreateTab(
		"Pose",
		"move-3d"
	)

TabPose:CreateSection(
	"Junta"
)

local JointDropdown =
	TabPose:CreateDropdown({
		Name =
			"Junta selecionada",

		Options = {
			"Selecione um rig"
		},

		CurrentOption = {},

		MultipleOptions = false,

		Flag = "Joint",

		Callback = function(opt)
			local key =
				first(opt)

			if State.KeyToMotor[key] then
				State.SelectedKey =
					key

				syncJointSliders()
			end
		end
	})

refreshJointUI = function()
	local options = {}

	for _, m in ipairs(
		State.Motors
	) do
		table.insert(
			options,
			State.MotorKeys[m]
		)
	end

	if #options == 0 then
		options = {
			"Selecione um rig"
		}
	end

	pcall(function()
		JointDropdown:Refresh(
			options
		)
	end)

	syncJointSliders()
end

local suppress = false
local JointSliders = {}

local function onJointChange()
	if suppress
		or not State.SelectedKey
	then
		return
	end

	local v =
		JointSliders

	State.Pose[
		State.SelectedKey
	] =
		poseFromValues(
			v.PX,
			v.PY,
			v.PZ,
			v.RX,
			v.RY,
			v.RZ
		)

	if State.AutoKey then
		commitKeyframe()
	end
end

local function jointSlider(
	name,
	key,
	range,
	increment,
	suffix
)
	local slider =
		TabPose:CreateSlider({
			Name = name,

			Range = range,

			Increment = increment,

			Suffix = suffix,

			CurrentValue = 0,

			Flag =
				"J_" .. key,

			Callback = function(value)
				JointSliders[key] =
					value

				onJointChange()
			end
		})

	JointSliders[key] = 0
	JointSliders["_" .. key] =
		slider
end

TabPose:CreateSection(
	"Rotação"
)

jointSlider(
	"Rotação X",
	"RX",
	{
		-180,
		180
	},
	1,
	"°"
)

jointSlider(
	"Rotação Y",
	"RY",
	{
		-180,
		180
	},
	1,
	"°"
)

jointSlider(
	"Rotação Z",
	"RZ",
	{
		-180,
		180
	},
	1,
	"°"
)

TabPose:CreateSection(
	"Posição"
)

jointSlider(
	"Posição X",
	"PX",
	{
		-5,
		5
	},
	0.05,
	""
)

jointSlider(
	"Posição Y",
	"PY",
	{
		-5,
		5
	},
	0.05,
	""
)

jointSlider(
	"Posição Z",
	"PZ",
	{
		-5,
		5
	},
	0.05,
	""
)

syncJointSliders = function()
	if not State.SelectedKey then
		return
	end

	local cf =
		State.Pose[
			State.SelectedKey
		]
		or CFrame.new()

	local px, py, pz,
		rx, ry, rz =
		valuesFromPose(cf)

	suppress = true

	local values = {
		PX = px,
		PY = py,
		PZ = pz,
		RX = rx,
		RY = ry,
		RZ = rz
	}

	for key, value in pairs(
		values
	) do

		JointSliders[key] =
			value

		pcall(function()
			JointSliders[
				"_" .. key
			]:Set(
				math.round(
					value * 100
				) / 100
			)
		end)
	end

	suppress = false
end

TabPose:CreateSection(
	"Ferramentas de Pose"
)

TabPose:CreateButton({
	Name =
		"Resetar junta selecionada",

	Callback = function()
		if State.SelectedKey then
			State.Pose[
				State.SelectedKey
			] =
				CFrame.new()

			syncJointSliders()

			if State.AutoKey then
				commitKeyframe()
			end
		end
	end
})

TabPose:CreateButton({
	Name =
		"Copiar pose desta junta para todas as 'Left'/'Right' opostas",

	Callback = function()
		local key =
			State.SelectedKey

		if not key then
			return
		end

		local opposite =
			key:find("Left")
			and key:gsub(
				"Left",
				"Right"
			)
			or (
				key:find("Right")
				and key:gsub(
					"Right",
					"Left"
				)
			)
			or nil

		if opposite
			and State.Pose[opposite] ~= nil
		then

			local cf =
				State.Pose[key]

			local px, py, pz,
				rx, ry, rz =
				valuesFromPose(cf)

			State.Pose[opposite] =
				poseFromValues(
					-px,
					py,
					pz,
					rx,
					-ry,
					-rz
				)

			notify(
				"Espelhado",
				key
					.. " → "
					.. opposite
			)

			if State.AutoKey then
				commitKeyframe()
			end
		else
			notify(
				"Sem oposto",
				"A junta não tem par Left/Right."
			)
		end
	end
})

TabPose:CreateButton({
	Name =
		"Interpolar pose atual com o próximo keyframe (50%)",

	Callback = function()
		local list =
			State.Anim.Keyframes

		local nextKf

		for _, k in ipairs(list) do
			if k.Time >
				State.Time + 0.0001
			then

				nextKf = k
				break
			end
		end

		if not nextKf then
			return
		end

		for key, cf in pairs(
			State.Pose
		) do

			State.Pose[key] =
				cf:Lerp(
					nextKf.Poses[key]
						or CFrame.new(),
					0.5
				)
		end

		syncJointSliders()
	end
})

TabPose:CreateSlider({
	Name =
		"Ruído aleatório na pose (todas as juntas)",

	Range = {
		0,
		30
	},

	Increment = 1,

	Suffix = "°",

	CurrentValue = 0,

	Flag = "Noise",

	Callback = function(value)
		if value <= 0 then
			return
		end

		local r =
			math.rad(value)

		for key, cf in pairs(
			State.Pose
		) do

			State.Pose[key] =
				cf
				* CFrame.Angles(
					(
						math.random()
						- 0.5
					) * r,

					(
						math.random()
						- 0.5
					) * r,

					(
						math.random()
						- 0.5
					) * r
				)
		end

		syncJointSliders()
	end
})

-- ───────────────────────────── Aba Cutscene ─────────────────────────

local TabCut =
	Window:CreateTab(
		"Cutscene",
		"clapperboard"
	)

TabCut:CreateSection(
	"Câmera Livre (WASD • Q/E sobe/desce • Botão direito gira • Shift acelera)"
)

TabCut:CreateToggle({
	Name = "Câmera livre",

	CurrentValue = false,

	Flag = "FreeCam",

	Callback =
		setFreeCam
})

TabCut:CreateSlider({
	Name =
		"Velocidade da câmera livre",

	Range = {
		5,
		200
	},

	Increment = 5,

	Suffix = "",

	CurrentValue = 40,

	Flag = "FreeCamSpeed",

	Callback = function(value)
		State.FreeCamSpeed =
			value
	end
})

TabCut:CreateSlider({
	Name =
		"FOV da câmera",

	Range = {
		10,
		120
	},

	Increment = 1,

	Suffix = "°",

	CurrentValue = 70,

	Flag = "FOV",

	Callback = function(value)
		workspace.CurrentCamera.FieldOfView =
			value
	end
})

TabCut:CreateButton({
	Name =
		"Olhar para o rig",

	Callback =
		focusOnRig
})

TabCut:CreateSection(
	"Keyframes de Câmera"
)

local CamDropdown =
	TabCut:CreateDropdown({
		Name =
			"Lista de câmeras",

		Options = {
			"Nenhum"
		},

		CurrentOption = {},

		MultipleOptions = false,

		Flag = "CamList",

		Callback = function(opt)
			local text =
				first(opt)

			local time =
				text
				and tonumber(
					text:match(
						"^([%d%.]+)s"
					)
				)

			if time then
				setTime(time)

				local ck =
					findCamKey(
						snapTime(time)
					)

				if ck then
					local currentCamera =
						workspace.CurrentCamera

					if not State.FreeCam then
						currentCamera.CameraType =
							Enum.CameraType.Scriptable
					end

					currentCamera.CFrame =
						ck.CFrame

					currentCamera.FieldOfView =
						ck.FOV
				end
			end
		end
	})

refreshCameraUI = function()
	local options = {}

	for _, ck in ipairs(
		State.CameraKeys
	) do

		table.insert(
			options,
			string.format(
				"%ss • FOV %d",
				fmt(ck.Time),
				ck.FOV
			)
		)
	end

	if #options == 0 then
		options = {
			"Nenhum"
		}
	end

	pcall(function()
		CamDropdown:Refresh(
			options
		)
	end)
end

TabCut:CreateButton({
	Name =
		"◆ Adicionar / Atualizar keyframe de câmera (posição atual)",

	Callback =
		addCameraKey
})

TabCut:CreateButton({
	Name =
		"Remover keyframe de câmera no tempo atual",

	Callback = function()
		local ck, index =
			findCamKey(
				snapTime(
					State.Time
				)
			)

		if ck then
			table.remove(
				State.CameraKeys,
				index
			)

			refreshCameraUI()
			refreshTimeline()
		end
	end
})

TabCut:CreateButton({
	Name =
		"Limpar keyframes de câmera",

	Callback = function()
		State.CameraKeys = {}

		refreshCameraUI()
		refreshTimeline()
	end
})

TabCut:CreateToggle({
	Name =
		"Preview da câmera ao arrastar a timeline",

	CurrentValue = false,

	Flag = "CamPreview",

	Callback = function(value)
		State.CameraPreview =
			value

		if not value
			and not State.FreeCam
			and not State.CutsceneActive
		then

			workspace.CurrentCamera.CameraType =
				Enum.CameraType.Custom
		end
	end
})

TabCut:CreateSection(
	"Reprodução da Cutscene"
)

TabCut:CreateButton({
	Name =
		"▶ Tocar cutscene (câmera + animação)",

	Callback =
		playCutscene
})

TabCut:CreateButton({
	Name =
		"■ Parar cutscene",

	Callback = function()
		State.Playing = false

		stopCutscene()

		setTime(0)
	end
})

TabCut:CreateToggle({
	Name =
		"Ocultar UI do Rayfield ao tocar (a timeline permanece)",

	CurrentValue = false,

	Flag = "HideUI",

	Callback = function(value)
		State.HideUIInCutscene =
			value
	end
})

TabCut:CreateSection(
	"Geradores de Câmera"
)

local orbit = {
	Radius = 12,
	Height = 4,
	Count = 8
}

TabCut:CreateSlider({
	Name =
		"Órbita • raio",

	Range = {
		2,
		60
	},

	Increment = 1,

	Suffix = "",

	CurrentValue = 12,

	Flag = "OrbR",

	Callback = function(value)
		orbit.Radius = value
	end
})

TabCut:CreateSlider({
	Name =
		"Órbita • altura",

	Range = {
		-10,
		30
	},

	Increment = 0.5,

	Suffix = "",

	CurrentValue = 4,

	Flag = "OrbH",

	Callback = function(value)
		orbit.Height = value
	end
})

TabCut:CreateSlider({
	Name =
		"Órbita • segmentos",

	Range = {
		4,
		32
	},

	Increment = 1,

	Suffix = "",

	CurrentValue = 8,

	Flag = "OrbC",

	Callback = function(value)
		orbit.Count = value
	end
})

TabCut:CreateButton({
	Name =
		"Gerar órbita ao redor do rig",

	Callback = function()
		generateOrbit(
			orbit.Radius,
			orbit.Height,
			orbit.Count
		)
	end
})

local dolly = {
	Start = 15,
	End = 4,
	Height = 2
}

TabCut:CreateSlider({
	Name =
		"Dolly • distância inicial",

	Range = {
		1,
		80
	},

	Increment = 1,

	Suffix = "",

	CurrentValue = 15,

	Flag = "DolS",

	Callback = function(value)
		dolly.Start = value
	end
})

TabCut:CreateSlider({
	Name =
		"Dolly • distância final",

	Range = {
		1,
		80
	},

	Increment = 1,

	Suffix = "",

	CurrentValue = 4,

	Flag = "DolE",

	Callback = function(value)
		dolly.End = value
	end
})

TabCut:CreateSlider({
	Name =
		"Dolly • altura",

	Range = {
		-10,
		30
	},

	Increment = 0.5,

	Suffix = "",

	CurrentValue = 2,

	Flag = "DolH",

	Callback = function(value)
		dolly.Height = value
	end
})

TabCut:CreateButton({
	Name =
		"Gerar dolly frontal (aproximação)",

	Callback = function()
		generateDolly(
			dolly.Start,
			dolly.End,
			dolly.Height
		)
	end
})

-- ───────────────────────────── Aba Efeitos ──────────────────────────

local TabFX =
	Window:CreateTab(
		"Efeitos",
		"sparkles"
	)

TabFX:CreateSection(
	"Cinema"
)

TabFX:CreateToggle({
	Name =
		"Letterbox (barras pretas)",

	CurrentValue = false,

	Flag = "Letterbox",

	Callback =
		setLetterbox
})

TabFX:CreateSlider({
	Name =
		"Altura do letterbox",

	Range = {
		0.02,
		0.3
	},

	Increment = 0.01,

	Suffix = "",

	CurrentValue = 0.12,

	Flag = "LBSize",

	Callback = function(value)
		FX.LetterboxSize =
			value

		if FX.Top.Size.Y.Scale > 0 then
			setLetterbox(true)
		end
	end
})

TabFX:CreateSlider({
	Name =
		"Duração do fade",

	Range = {
		0.1,
		5
	},

	Increment = 0.1,

	Suffix = "s",

	CurrentValue = 1,

	Flag = "FadeDur",

	Callback = function(value)
		FX.FadeDuration =
			value
	end
})

TabFX:CreateButton({
	Name =
		"Fade para preto",

	Callback = function()
		fade(true)
	end
})

TabFX:CreateButton({
	Name =
		"Fade de volta",

	Callback = function()
		fade(false)
	end
})

TabFX:CreateColorPicker({
	Name =
		"Cor do fade/letterbox",

	Color =
		Color3.new(
			0,
			0,
			0
		),

	Flag = "FadeColor",

	Callback = function(color)
		FX.Fade.BackgroundColor3 =
			color

		FX.Top.BackgroundColor3 =
			color

		FX.Bottom.BackgroundColor3 =
			color
	end
})

TabFX:CreateSection(
	"Câmera"
)

TabFX:CreateSlider({
	Name =
		"Tremor de câmera (shake)",

	Range = {
		0,
		1
	},

	Increment = 0.05,

	Suffix = "",

	CurrentValue = 0,

	Flag = "Shake",

	Callback = function(value)
		State.Shake = value
	end
})

TabFX:CreateSlider({
	Name =
		"Blur",

	Range = {
		0,
		40
	},

	Increment = 1,

	Suffix = "",

	CurrentValue = 0,

	Flag = "Blur",

	Callback = function(value)
		local blur =
			getLightingEffect(
				"BlurEffect",
				"LunarBlur"
			)

		blur.Size = value
		blur.Enabled =
			value > 0
	end
})

TabFX:CreateSlider({
	Name =
		"Saturação",

	Range = {
		-1,
		1
	},

	Increment = 0.05,

	Suffix = "",

	CurrentValue = 0,

	Flag = "Sat",

	Callback = function(value)
		getLightingEffect(
			"ColorCorrectionEffect",
			"LunarCC"
		).Saturation = value
	end
})

TabFX:CreateSlider({
	Name =
		"Contraste",

	Range = {
		-1,
		1
	},

	Increment = 0.05,

	Suffix = "",

	CurrentValue = 0,

	Flag = "Contrast",

	Callback = function(value)
		getLightingEffect(
			"ColorCorrectionEffect",
			"LunarCC"
		).Contrast = value
	end
})

TabFX:CreateSlider({
	Name =
		"Brilho",

	Range = {
		-1,
		1
	},

	Increment = 0.05,

	Suffix = "",

	CurrentValue = 0,

	Flag = "Bright",

	Callback = function(value)
		getLightingEffect(
			"ColorCorrectionEffect",
			"LunarCC"
		).Brightness = value
	end
})

TabFX:CreateColorPicker({
	Name =
		"Tint (cor da cena)",

	Color =
		Color3.new(
			1,
			1,
			1
		),

	Flag = "Tint",

	Callback = function(color)
		getLightingEffect(
			"ColorCorrectionEffect",
			"LunarCC"
		).TintColor = color
	end
})

TabFX:CreateButton({
	Name =
		"Resetar efeitos de Lighting",

	Callback = function()
		for _, name in ipairs({
			"LunarBlur",
			"LunarCC"
		}) do

			local effect =
				Lighting:FindFirstChild(
					name
				)

			if effect then
				effect:Destroy()
			end
		end

		State.Shake = 0

		notify(
			"Efeitos resetados",
			"Blur e correção de cor removidos."
		)
	end
})

TabFX:CreateSection(
	"Cena"
)

TabFX:CreateToggle({
	Name =
		"Ocultar meu personagem",

	CurrentValue = false,

	Flag = "HideChar",

	Callback = function(value)
		local character =
			LocalPlayer.Character

		if not character
			or character == State.Rig
		then
			return
		end

		for _, d in ipairs(
			character:GetDescendants()
		) do

			if d:IsA("BasePart") then
				d.LocalTransparencyModifier =
					value
					and 1
					or 0
			end

			if d:IsA("Decal") then
				d.Transparency =
					value
					and 1
					or 0
			end
		end
	end
})

TabFX:CreateSlider({
	Name =
		"Hora do dia (Lighting.ClockTime)",

	Range = {
		0,
		24
	},

	Increment = 0.25,

	Suffix = "h",

	CurrentValue =
		Lighting.ClockTime,

	Flag = "Clock",

	Callback = function(value)
		Lighting.ClockTime =
			value
	end
})

-- ───────────────────────────── Aba Exportar ─────────────────────────

local TabExp =
	Window:CreateTab(
		"Exportar",
		"download"
	)

TabExp:CreateSection(
	"KeyframeSequence"
)

TabExp:CreateButton({
	Name =
		"Tocar via Animator (registra KeyframeSequence • Studio)",

	Callback =
		playViaAnimator
})

TabExp:CreateButton({
	Name =
		"Copiar código Lua da KeyframeSequence",

	Callback = function()
		local code =
			exportLuaCode()

		if copyToClipboard(code) then
			notify(
				"Copiado",
				"Código Lua copiado. Cole na Command Bar do Studio."
			)
		else
			print(code)

			notify(
				"Impresso",
				"Sem clipboard: o código foi impresso no Output."
			)
		end
	end
})

TabExp:CreateSection(
	"Projeto (JSON)"
)

TabExp:CreateButton({
	Name =
		"Copiar projeto em JSON",

	Callback = function()
		local json =
			serializeProject()

		if copyToClipboard(json) then
			notify(
				"Copiado",
				"JSON do projeto copiado."
			)
		else
			print(json)

			notify(
				"Impresso",
				"JSON impresso no Output."
			)
		end
	end
})

TabExp:CreateInput({
	Name =
		"Importar projeto (colar JSON)",

	PlaceholderText =
		"{...}",

	RemoveTextAfterFocusLost =
		true,

	Callback = function(text)
		if text
			and #text > 2
		then
			importProject(text)
		end
	end
})

TabExp:CreateParagraph({
	Title =
		"Como usar a exportação",

	Content =
		"1) Copie o código Lua. 2) No Studio, cole na Command Bar e execute. 3) A KeyframeSequence aparece em ServerStorage."
})

-- ───────────────────────────── Configurações ────────────────────────

local TabCfg =
	Window:CreateTab(
		"Configurações",
		"settings"
	)

TabCfg:CreateSection(
	"Tamanho e Tema"
)

TabCfg:CreateSlider({
	Name =
		"Escala da interface",

	Range = {
		0.6,
		1.6
	},

	Increment = 0.05,

	Suffix = "x",

	CurrentValue = 1,

	Flag = "UIScale",

	Callback = function(value)
		State.Settings.Scale =
			value

		applyVisuals()
	end
})

TabCfg:CreateDropdown({
	Name =
		"Tema do Rayfield",

	Options =
		THEMES,

	CurrentOption = {
		"Default"
	},

	MultipleOptions = false,

	Flag = "Theme",

	Callback = function(opt)
		State.Settings.Theme =
			first(opt)

		pcall(function()
			Window:ModifyTheme(
				State.Settings.Theme
			)
		end)

		State.MainOrigColor = nil

		task.delay(
			0.3,
			applyVisuals
		)
	end
})

TabCfg:CreateSection(
	"Gradientes"
)

TabCfg:CreateToggle({
	Name =
		"Gradiente na janela e na timeline",

	CurrentValue = true,

	Flag = "Grad",

	Callback = function(value)
		State.Settings.GradientEnabled =
			value

		applyVisuals()
	end
})

TabCfg:CreateColorPicker({
	Name =
		"Cor A do gradiente",

	Color =
		State.Settings.GradA,

	Flag = "GradA",

	Callback = function(color)
		State.Settings.GradA =
			color

		applyVisuals()
		refreshTimeline()
	end
})

TabCfg:CreateColorPicker({
	Name =
		"Cor B do gradiente",

	Color =
		State.Settings.GradB,

	Flag = "GradB",

	Callback = function(color)
		State.Settings.GradB =
			color

		applyVisuals()
		refreshTimeline()
	end
})

TabCfg:CreateSlider({
	Name =
		"Rotação do gradiente",

	Range = {
		0,
		360
	},

	Increment = 5,

	Suffix = "°",

	CurrentValue = 35,

	Flag = "GradRot",

	Callback = function(value)
		State.Settings.GradRotation =
			value

		applyVisuals()
	end
})

TabCfg:CreateToggle({
	Name =
		"Gradiente animado",

	CurrentValue = true,

	Flag = "GradAnim",

	Callback = function(value)
		State.Settings.AnimatedGradient =
			value
	end
})

TabCfg:CreateButton({
	Name =
		"Preset: Lunar (azul → ciano)",

	Callback = function()
		State.Settings.GradA =
			Color3.fromRGB(
				28,
				36,
				74
			)

		State.Settings.GradB =
			Color3.fromRGB(
				44,
				150,
				170
			)

		applyVisuals()
		refreshTimeline()
	end
})

TabCfg:CreateButton({
	Name =
		"Preset: Pôr do sol (vinho → laranja)",

	Callback = function()
		State.Settings.GradA =
			Color3.fromRGB(
				80,
				24,
				48
			)

		State.Settings.GradB =
			Color3.fromRGB(
				230,
				120,
				60
			)

		applyVisuals()
		refreshTimeline()
	end
})

TabCfg:CreateButton({
	Name =
		"Preset: Floresta (verde escuro → lima)",

	Callback = function()
		State.Settings.GradA =
			Color3.fromRGB(
				20,
				50,
				40
			)

		State.Settings.GradB =
			Color3.fromRGB(
				120,
				200,
				90
			)

		applyVisuals()
		refreshTimeline()
	end
})

TabCfg:CreateSection(
	"Timeline"
)

TabCfg:CreateToggle({
	Name =
		"Mostrar timeline",

	CurrentValue = true,

	Flag = "TLVisible",

	Callback = function(value)
		State.Settings.TimelineVisible =
			value

		applyVisuals()
	end
})

TabCfg:CreateSlider({
	Name =
		"Largura da timeline",

	Range = {
		480,
		1400
	},

	Increment = 10,

	Suffix = "px",

	CurrentValue = 820,

	Flag = "TLWidth",

	Callback = function(value)
		State.Settings.TimelineWidth =
			value

		applyVisuals()
	end
})

TabCfg:CreateSlider({
	Name =
		"Transparência do fundo da timeline",

	Range = {
		0,
		0.9
	},

	Increment = 0.05,

	Suffix = "",

	CurrentValue = 0.35,

	Flag = "TLOpacity",

	Callback = function(value)
		State.Settings.TimelineOpacity =
			value

		applyVisuals()
	end
})

TabCfg:CreateSection(
	"Atalhos"
)

TabCfg:CreateKeybind({
	Name =
		"Play / Pause",

	CurrentKeybind =
		Enum.KeyCode.P,

	HoldToInteract = false,

	Flag = "KB_Play",

	Callback = function()
		togglePlay()
	end
})

TabCfg:CreateKeybind({
	Name =
		"Adicionar keyframe",

	CurrentKeybind =
		Enum.KeyCode.K,

	HoldToInteract = false,

	Flag = "KB_Key",

	Callback = function()
		commitKeyframe()
	end
})

TabCfg:CreateKeybind({
	Name =
		"Keyframe de câmera",

	CurrentKeybind =
		Enum.KeyCode.C,

	HoldToInteract = false,

	Flag = "KB_Cam",

	Callback = function()
		addCameraKey()
	end
})

TabCfg:CreateKeybind({
	Name =
		"Keyframe anterior",

	CurrentKeybind =
		Enum.KeyCode.Comma,

	HoldToInteract = false,

	Flag = "KB_Prev",

	Callback = function()
		jumpKeyframe(-1)
	end
})

TabCfg:CreateKeybind({
	Name =
		"Próximo keyframe",

	CurrentKeybind =
		Enum.KeyCode.Period,

	HoldToInteract = false,

	Flag = "KB_Next",

	Callback = function()
		jumpKeyframe(1)
	end
})

TabCfg:CreateSection(
	"Sistema"
)

TabCfg:CreateButton({
	Name =
		"Fechar Lunar Animator",

	Callback = function()
		State.Playing = false

		stopCutscene()

		setFreeCam(false)

		if State.Rig then
			for _, m in ipairs(
				State.Motors
			) do
				pcall(function()
					m.Transform =
						CFrame.new()
				end)
			end
		end

		if TL.Gui then
			TL.Gui:Destroy()
		end

		for _, name in ipairs({
			"LunarBlur",
			"LunarCC"
		}) do

			local effect =
				Lighting:FindFirstChild(
					name
				)

			if effect then
				effect:Destroy()
			end
		end

		local fx =
			PlayerGui:FindFirstChild(
				"LunarFX"
			)

		if fx then
			fx:Destroy()
		end

		pcall(function()
			Rayfield:Destroy()
		end)
	end
})

-- ───────────────────────────── Inicialização ─────────────────────────

buildTimeline()

refreshTimeline()

task.delay(
	1,
	applyVisuals
)

-- ───────────────────────────── Loop ─────────────────────────────────

RunService.Stepped:Connect(
	function(_, dt)
		if State.Playing then
			State.Time +=
				dt
				* State.Anim.Speed

			if State.Time >
				State.Anim.Length
			then

				if State.Anim.Loop then
					State.Time =
						State.Time
						% State.Anim.Length
				else
					State.Time =
						State.Anim.Length

					State.Playing = false

					if State.CutsceneActive then
						task.delay(
							0.1,
							stopCutscene
						)
					end
				end
			end

			if #State.Anim.Keyframes > 0 then
				State.Pose =
					samplePose(
						State.Time
					)
			end
		end

		if State.ApplyPose
			and State.Rig
			and State.Rig.Parent
		then

			for m, key in pairs(
				State.MotorKeys
			) do

				if m.Parent then
					m.Transform =
						State.Pose[key]
						or CFrame.new()
				end
			end
		end
	end
)

-- ───────────────────────────── Render ───────────────────────────────

local gradientClock = 0

RunService.RenderStepped:Connect(
	function(dt)
		local currentCamera =
			workspace.CurrentCamera

		-- Câmera

		if State.FreeCam then
			updateFreeCam(dt)

		elseif (
			State.CutsceneActive
			or (
				State.CameraPreview
				and not State.Playing
			)
		)
			and #State.CameraKeys > 0
		then

			currentCamera.CameraType =
				Enum.CameraType.Scriptable

			local cf, fov =
				sampleCamera(
					State.Time
				)

			if cf then
				if State.Shake > 0 then
					local t =
						os.clock()
						* 14

					cf =
						cf
						* CFrame.Angles(
							math.noise(
								t,
								0
							)
								* State.Shake
								* 0.04,

							math.noise(
								0,
								t
							)
								* State.Shake
								* 0.04,

							math.noise(
								t,
								t
							)
								* State.Shake
								* 0.02
						)
				end

				currentCamera.CFrame =
					cf

				currentCamera.FieldOfView =
					fov or 70
			end
		end

		-- Timeline

		if TL.Root
			and TL.Root.Visible
		then

			refreshTimeline(true)

			if State.Playing
				and State.Settings.AnimatedGradient
			then

				TL.Scrub.BackgroundTransparency =
					0.15
					+ 0.15
					* math.sin(
						os.clock()
						* 6
					)
			else
				TL.Scrub.BackgroundTransparency =
					0
			end
		end

		-- Gradiente

		if State.Settings.GradientEnabled
			and State.Settings.AnimatedGradient
		then

			gradientClock += dt

			local rotation =
				State.Settings.GradRotation
				+ math.sin(
					gradientClock
					* 0.6
				)
				* 25

			if TL.Grad then
				TL.Grad.Rotation =
					rotation
			end

			local gui =
				findRayfieldGui()

			local main =
				gui
				and gui:FindFirstChild(
					"Main"
				)

			local gradient =
				main
				and main:FindFirstChild(
					"LunarGradient"
				)

			if gradient then
				gradient.Rotation =
					rotation
			end
		end
	end
)

-- ───────────────────────────── Atualização da Timeline ──────────────

do
	local lastCurrent

	RunService.Heartbeat:Connect(
		function()
			local current =
				findKeyframe(
					snapTime(
						State.Time
					)
				)

			if current
				~= lastCurrent
			then

				lastCurrent =
					current

				refreshTimeline()
			end
		end
	)
end

notify(
	"Lunar Animator",
	"Carregado! Selecione um rig na aba Rig. RightShift alterna a UI.",
	6
)