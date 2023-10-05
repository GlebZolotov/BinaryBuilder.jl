using HTTP
using JSON
using URIs

function project_id(repo_url)
    return URIs.escapeuri(repo_url[length("https://gitlab.com/") + 1:end])
end

function is_gitlab_repo_exists(repo_url, token)
    repo_path = project_id(repo_url)
    resp = HTTP.request("GET", "https://gitlab.com/api/v4/projects/$(repo_path)", headers=["PRIVATE-TOKEN" => token], status_exception=false)
    return resp.status == 200
end

function create_gitlab_repo(repo_url, token)
    name = repo_url[findlast("/", repo_url)[1] + 1:end]
    if length("https://gitlab.com/") + 1 < findlast("/", repo_url)[1] - 1
        namespace = URIs.escapeuri(repo_url[length("https://gitlab.com/") + 1:findlast("/", repo_url)[1] - 1])
        resp = HTTP.request("GET", "https://gitlab.com/api/v4/namespaces/$(namespace)", headers=["PRIVATE-TOKEN" => token])
        namespace_id = string(JSON.parse(String(resp.body))["id"])
    else
        namespace_id = nothing
    end

    body = Dict("path" => name)
    isnothing(namespace_id) || (body["namespace_id"] = namespace_id)
    println(body)
    HTTP.request("POST", "https://gitlab.com/api/v4/projects", 
                 headers=["PRIVATE-TOKEN" => token, "Content-Type" => "application/json"], 
                 body=JSON.json(body))
end

function upload_file(path, repo, token)
    open(path) do io
        data = [
            "file" => io,
        ]
        body = HTTP.Form(data)

        resp = HTTP.request("POST", "https://gitlab.com/api/v4/projects/$(project_id(repo))/uploads", 
                        headers=["PRIVATE-TOKEN" => token], 
                        body=body)

        return JSON.parse(String(resp.body))
    end
end

function upload_to_gitlab_releases(repo, tag, path; attempts::Int = 3, verbose::Bool = false)
    token = get(ENV, "GITLAB_TOKEN", "")
    links = map(readdir(path)) do name
        res = upload_file(joinpath(path, name), repo, token)
        return Dict(
            "name" => name, 
            "url" => "https://gitlab.com" * res["full_path"],
            "direct_asset_path" => name
        )
    end
    
    body = Dict("tag_name" => tag, "ref" => "main", "assets" => Dict("links" => links))

    for attempt in 1:attempts
        try
            HTTP.request("POST", "https://gitlab.com/api/v4/projects/$(project_id(repo))/releases", 
                 headers=["PRIVATE-TOKEN" => token, "Content-Type" => "application/json"], 
                 body=JSON.json(body))
            return
        catch
            if verbose
                @info("`gitlab api` upload step failed, beginning attempt #$(attempt)...")
            end
        end
    end
    error("Unable to upload $(path) to GitLab repo $(repo) on tag $(tag)")
end