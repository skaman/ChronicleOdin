@echo off

REM Run from root directory
if not exist "%cd%\bin\assets\shaders" mkdir "%cd%\bin\assets\shaders"

echo "Compiling shaders..."

echo "assets\shaders\builtin_object_shader.vert.glsl -> bin\assets\shaders\builtin_object_shader.vert.spv"
%VULKAN_SDK%\Bin\glslc.exe -fshader-stage=vert "%cd%\assets\shaders\builtin_object_shader.vert.glsl" -o "%cd%\bin\assets\shaders\builtin_object_shader.vert.spv"
IF %ERRORLEVEL% NEQ 0 (echo Error: %ERRORLEVEL% && exit)

echo "assets\shaders\builtin_object_shader.frag.glsl -> bin\assets\shaders\builtin_object_shader.frag.spv"
%VULKAN_SDK%\Bin\glslc.exe -fshader-stage=frag "%cd%\assets\shaders\builtin_object_shader.frag.glsl" -o "%cd%\bin\assets\shaders\builtin_object_shader.frag.spv"
IF %ERRORLEVEL% NEQ 0 (echo Error: %ERRORLEVEL% && exit)

echo "Copying assets..."
xcopy "%cd%\assets" "%cd%\bin\assets" /h /i /c /k /e /r /y

echo "Done."