function table.shallow_copy(t)
    local t2 = {}
    for k,v in pairs(t) do
      t2[k] = v
    end
    return t2
  end

function getXAndY(index, width)
    local x = index % width
    local y = index // width
    return x, y
end

function getFromXAndY(x, y, width)
    return x + y * width
end

function isAlphaChannelSolidFromCoordinate(x, y, pixels, width, height)
    if (x < 0 or x >= width or y < 0 or y >= height) then
        return nil
    end

    local pixel = pixels[getFromXAndY(x, y, width)]
    return isAlphaChannelSolidFromPixel(pixel)
end

function isAlphaChannelSolidFromPixel(pixel)    
    local alphaChannel = app.pixelColor.rgbaA(pixel)
    return alphaChannel == 255
end

function generateArrayRepresentation(image)
    local array = {}
    local i = 0
    for it in image:pixels() do
        array[i] = it()
        i = i + 1 
    end
    return array
end

function copyToImageFromPixelArray(image, pixels)
    for it in image:pixels() do    
        it(pixels[getFromXAndY(it.x, it.y, image.width)])
    end
end

function getBorders(pixels, width, height)
    local border = {}
    for i, it in ipairs(pixels) do
        if not isAlphaChannelSolidFromPixel(it) then
            --Search at least one solid neightbour, if so, added to the boarders           
            local x,y = getXAndY(i, width)
            if (isAlphaChannelSolidFromCoordinate(x - 1, y, pixels, width, height)
                or isAlphaChannelSolidFromCoordinate(x + 1, y, pixels, width, height)
                or isAlphaChannelSolidFromCoordinate(x, y - 1, pixels, width, height)
                or isAlphaChannelSolidFromCoordinate(x, y + 1, pixels, width, height)) then
                table.insert(border, Point(x, y))
            end
        end
    end
    return border
end

function calculateChannels(channels, pixels, x, y, width, height)
    local isSolid = isAlphaChannelSolidFromCoordinate(x, y, pixels, width, height)    
    if isSolid then
        local pixel = pixels[getFromXAndY(x, y, width)]
        channels.red = app.pixelColor.rgbaR(pixel) + channels.red
        channels.green = app.pixelColor.rgbaG(pixel) + channels.green
        channels.blue = app.pixelColor.rgbaB(pixel) + channels.blue
        channels.accumulated = channels.accumulated + 1    
    elseif isSolid ~= nil then
        return false
    end
    return true
end

function iterateAndSample(inputPixels, outputPixels, border, width, height)    
    local newBorder = {}
    local alreadyExplored = {}
    for _, point in ipairs(border) do    
        local channels = { red=0, green=0, blue=0, accumulated=0 }
        
        if not calculateChannels(channels, inputPixels, point.x - 1, point.y, width, height) and alreadyExplored[point.x - 1 .. point.y] ~= true then
            table.insert(newBorder, Point(point.x - 1, point.y))
            alreadyExplored[point.x - 1 .. point.y] = true
        end

        if not calculateChannels(channels, inputPixels, point.x + 1, point.y, width, height) and alreadyExplored[point.x + 1 .. point.y] ~= true then
            table.insert(newBorder, Point(point.x + 1, point.y))
            alreadyExplored[point.x + 1 .. point.y] = true
        end

        if not calculateChannels(channels, inputPixels, point.x, point.y - 1, width, height) and alreadyExplored[point.x.. point.y - 1] ~= true then
            table.insert(newBorder, Point(point.x, point.y - 1))
            alreadyExplored[point.x .. point.y - 1] = true
        end

        if not calculateChannels(channels, inputPixels, point.x, point.y + 1, width, height) and alreadyExplored[point.x .. point.y + 1] ~= true then
            table.insert(newBorder, Point(point.x, point.y + 1))
            alreadyExplored[point.x .. point.y + 1] = true
        end
        if channels.accumulated > 0 then
            local red = channels.red / channels.accumulated
            local green = channels.green / channels.accumulated
            local blue = channels.blue / channels.accumulated

            local color = app.pixelColor.rgba(red, green, blue, 255)
            outputPixels[getFromXAndY(point.x, point.y, width)] = color
        end       
    end
    return newBorder
end

app.transaction(
    function()
        local sprite = app.activeSprite
        if not sprite then 
            return app.alert("There is no active sprite") 
        end

        local cel = app.activeCel
        if not cel then	
            return app.alert("There is no active image")
        end

        local fileExtension = app.fs.fileExtension(sprite.filename)
        if string.upper(fileExtension) ~= "PNG" then
            return app.alert("The file extension must be PNG to run this script")
        end

        local dialog = Dialog("UV Padder")
        dialog
            :label{ id="label", text="This script creates an automatic padder in the texture." }
            :newrow()
            :label{ id="label", text="This process could take some time to complete," }
            :newrow()
            :label{ id="label", text="let the script run even if the window seems crashed" }
            :newrow()
            :label{ id="label", text="or not responding." }
            :newrow()
            :separator{ text="Select an algorithm" }
            :radio{ id="fastForward", text="Fast Forward", selected=true }
            :newrow()
            :radio{ id="singlePass", text="Single Pass" }
            :newrow()
            :radio{ id="doublePass", text="Double Pass" }
            :newrow()
            :separator()
            :button{ id="ok", text="Ok" }
            :button{ id="cancel", text="Cancel" }
            :show()

        local data = dialog.data
        if not data.ok then
            return
        end        

        local imagePosition = cel.position
        cel.position = Point(0,0)

        local inputImage = Image(sprite.width, sprite.height)
        inputImage:drawImage(cel.image:clone(), imagePosition)

        local inputPixels = generateArrayRepresentation(inputImage)
        local outputPixels = generateArrayRepresentation(inputImage)

        local border = getBorders(inputPixels, sprite.width, sprite.height)
        
        if #border == inputImage.width * inputImage.height then
            return app.alert("There are no solid pixels in the image.")
        end
                      
        while #border > 0
        do
            local newBorder = nil
            --Fast forward
            if data.fastForward then
                newBorder = iterateAndSample(outputPixels, outputPixels, border, sprite.width, sprite.height)                
            end
            --Single pass
            if data.singlePass then
                newBorder = iterateAndSample(inputPixels, outputPixels, border, sprite.width, sprite.height)
                inputPixels = table.shallow_copy(outputPixels)                
            end
            --Double pass - Review this, not working as expected
            if data.doublePass then
                newBorder = iterateAndSample(inputPixels, outputPixels, border, sprite.width, sprite.height)
                iterateAndSample(outputPixels, inputPixels, border, sprite.width, sprite.height)            
                outputPixels = table.shallow_copy(inputPixels)                
            end

            border = newBorder
        end

        copyToImageFromPixelArray(inputImage, outputPixels)
        cel.image = inputImage
    end
)