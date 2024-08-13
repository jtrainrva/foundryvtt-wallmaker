using JSON
using Meshes
using ConcaveHull
using Random
using Images
using FileIO
using Random
using Unitful
using ArgParse
using Interpolations

function process_map(img_input,json_input,json_output,max_px,selinger_eps,concave_k)

    # Set a seed for testing purposes.
    # There's no reason it should impact anything else
    Random.seed!(1704)

    img = FileIO.load(img_input)

    map_json = JSON.parsefile(json_input::AbstractString; dicttype=Dict, inttype=Int64, use_mmap=true)
    if !haskey(map_json,"walls")
        map_json["walls"]=[]
    end
    
    # Set padding to 0 for simplicity
    map_json["padding"]=0.0
    
    # Scale image to size listed in json
    #img = imresize(img,(map_json["height"],map_json["width"]), method=BSpline(Constant()))

    scale_ratio = max_px/maximum(size(img))

    im_small = imresize(img,ratio=scale_ratio, method=BSpline(Constant()))

    im2 = channelview(im_small)

    # Black is the background color
    # Get all other unique colors
    im2 = mapslices(Tuple,im2,dims=[1])[1,:,:]

    u_v = unique(im2[:])
    if length(u_v[1]) == 4
        u_v = u_v[map((x)->x!=(0,0,0,1),u_v)] # Throw away black
    elseif length(u_v[1]) == 3
        u_v = u_v[map((x)->x!=(0,0,0),u_v)] # Throw away black
    else
        println("Unrecognized image format!")
    end
    
    # Iterate through colors
    for u in u_v
        eps = 2e-2
        
        im_bool = map((x)->x==u,im2)

        points = Vector{Vector{Float64}}(undef,sum(im_bool))
        counter = 1
        for i in eachindex(view(im2,1:size(im2)[1],1:size(im_bool)[2]))
            if im_bool[i]
                points[counter]=collect(Tuple(i))
                counter += 1
            end
        end
        

        rpoints = map((x)->x+eps*(rand(Float64,(2)).- 0.5),points)

        hull = concave_hull(rpoints,concave_k)

        pset = PolyArea(map(Tuple,hull.vertices))

        simp1 = simplify(pset, Selinger(selinger_eps))

        # Now add points to json
        #    {
        #  "light": 20, <-- Values for standard wall
        #  "sight": 20,
        #  "sound": 20,
        #  "move": 20,
        #  "c": [   <-- y1,x1,y2,x2 order
        #    2212,
        #    1812,
        #    2812,
        #    1812
        #  ],
        #  "_id": "TCQ3sfq9co8gkKeW", <-- Random id here
        #  "dir": 0,
        #  "door": 0,
        #  "ds": 0,
        #  "threshold": {
        #    "light": null,
        #    "sight": null,
        #    "sound": null,
        #    "attenuation": false
        #  },
        #  "flags": {}
        #}
        #
        # For now, assuming a basic wall with no door
        # Dont forget to close the ring manually

        # Rescale
        pts = map(
            (vert)->round.(Int,ustrip.((vert.coords.x,vert.coords.y))./scale_ratio),
            simp1.rings[1].vertices)

        wall_array = Vector{Dict{String,Any}}(undef,size(pts)[1])
        
        # Create threshold dictionary
        thresh_dict = Dict(
            "light"=>nothing,
            "sight"=>nothing,
            "sound"=>nothing,
            "attenuation"=>false
        )
        # Circular vector, so nothing to do about end
        for i in 1:(size(pts)[1])
            wall_array[i] = Dict(
                "light"=>20,
                "sight"=>20,
                "sound"=>20,
                "move"=>20,
                "c"=>[pts[i][2],pts[i][1],pts[i+1][2],pts[i+1][1]],
                "_id"=> randstring(16),
                "dir"=>0,
                "door"=>0,
                "ds"=>0,
                "threshold"=>thresh_dict,
                "flags"=>Dict()
            )
        end
         # Append to walls
        append!(map_json["walls"],wall_array)
    end

    
    # Output to new? file
    open(json_output,"w") do f
        JSON.print(f, map_json)
    end
    return 0
end

function parse_commandline()
    s = ArgParseSettings()

    @add_arg_table s begin
        "--output_json", "-o"
            help = "JSON with added walls filename. Defaults to input_json_withwalls"
            arg_type = String
        "--max-px"
            help = "Input image is downscaled while preserving aspect ratio to an image with a maximum size length of max_px."
            arg_type = Int
            default = 500
        "--concave-k"
            help = "Controls the number of nearest neighbors used in concave hull finding algorith. Higher is smoother."
            arg_type = Int
            default = 5
        "--selinger-eps"
            help = "Concave hull postprocessed with Selinger's algorithm (see Meshes.jl). This controls the level of simplification. Higher is simpler."
            arg_type = Real
            default = 0.5
        "input_image"
            help = "Input image. See README."
            required = true
        "input_json"
            help = "FoundryVTT scene JSON file. See 'Importing from JSON files' under 'Importing Pre-configured Scenes' at https://foundryvtt.com/article/scenes/" 
            required = true
    end

    return parse_args(s)
end

function main()
    cmd_args = parse_commandline()

    if isnothing(cmd_args["output_json"])
        cmd_args["output_json"] = (cmd_args["input_json"])[1:end-5]*"_withwalls.json"
    end

    #print(cmd_args)

    process_map(
        cmd_args["input_image"],
        cmd_args["input_json"],
        cmd_args["output_json"],
        cmd_args["max-px"],
        cmd_args["selinger-eps"],
        cmd_args["concave-k"])
end

main()
