using Test
import UUIDs
import Pluto: PlutoRunner, Notebook, WorkspaceManager, Cell, ServerSession, ClientSession, update_run!
using Pluto.WorkspaceManager: poll

@testset "Logging" begin
    🍭 = ServerSession()
    🍭.options.evaluation.workspace_use_distributed = true

    notebook = Notebook(Cell.([
        "println(123)",
        "println(stdout, 123)",
        "println(stderr, 123)",
        "display(123)",
        "show(123)",
        "popdisplay()",
        "println(123)",
        "pushdisplay(TextDisplay(devnull))",
        "print(12); print(3)", # 9
        
        """
        for i in 1:10
            @info "logging" i maxlog=2
        end
        """, # 10
        
        """
        for i in 1:10
            @info "logging" i maxlog=2
            @info "logging more" maxlog = 4
            @info "even more logging"
        end
        """, # 11
    ]))
    
    
    @testset "Stdout" begin
        
        idx_123 = [1,2,3,4,5,7,9]

        update_run!(🍭, notebook, notebook.cells[1:9])
        @test notebook.cells[1] |> noerror
        @test notebook.cells[2] |> noerror
        @test notebook.cells[3] |> noerror
        @test notebook.cells[4] |> noerror
        @test notebook.cells[5] |> noerror
        @test notebook.cells[6] |> noerror
        @test notebook.cells[7] |> noerror
        @test notebook.cells[8] |> noerror
        @test notebook.cells[9] |> noerror

        @test poll(5, 1/60) do
            all(notebook.cells[idx_123]) do c
                length(c.logs) == 1
            end
        end
        
        @testset "123 - $(i)" for i in idx_123
            log = only(notebook.cells[i].logs)
            @test log["level"] == "LogLevel(-555)"
            @test strip(log["msg"][1]) == "123"
            @test log["msg"][2] == MIME"text/plain"()
        end
    end

    @testset "Logging respects maxlog" begin
        @testset "Single log" begin
            
            update_run!(🍭, notebook, notebook.cells[10])
            @test notebook.cells[10] |> noerror

            @test poll(5, 1/60) do
                length(notebook.cells[10].logs) == 2
            end

            # Check that maxlog doesn't occur in the message
            @test all(notebook.cells[10].logs) do log
                all(log["kwargs"]) do kwarg
                    kwarg[1] != "maxlog"
                end
            end

        end

        @testset "Multiple log" begin
            update_run!(🍭, notebook, notebook.cells[11])
            @test notebook.cells[11] |> noerror

            # Wait until all 16 logs are in
            @test poll(5, 1/60) do
                length(notebook.cells[11].logs) == 16
            end

            # Get the ids of the three logs and their counts. We are
            # assuming that the logs are ordered same as in the loop.
            ids = unique(getindex.(notebook.cells[11].logs, "id"))
            counts = [count(log -> log["id"] == id, notebook.cells[11].logs) for id in ids]
            @test counts == [2, 4, 10]

            # Check that maxlog doesn't occur in the messages
            @test all(notebook.cells[11].logs) do log
                all(log["kwargs"]) do kwarg
                    kwarg[1] != "maxlog"
                end
            end
        end
    end

    WorkspaceManager.unmake_workspace((🍭, notebook))
end
