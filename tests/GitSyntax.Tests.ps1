using module ..\CmdUsageSyntax

Describe GitSyntax {
    Context "Git root command" {
        $usage = "git [--version] [--help] [-C <path>] [-c name=value] [--exec-path[=<path>]] [--html-path] [--man-path] [--info-path] [-p | --paginate | --no-pager] [--no-replace-objects] [--bare] [--git-dir=<path>] [--work-tree=<path>] [--namespace=<name>] <command> [<args>]"
        
        $syntaxTree = New-CmdUsageSyntaxNode -Usage $usage
        
        function GetOptionalParameter($parameterName) {
            $syntaxTree | ? {
                $_ -is [BracketedNode]
            } | % {
                $_.Contents[0]
            } | ? {
                ($_ -is [ParameterNode]) -and ($_.Text -eq $parameterName)
            } | select -First 1
        }
        
        It "should start with git" {
            $syntaxTree[0].Text | should be git
        }
        
        It "should have a node with -p | --paginate | --no-pager" {
            $orNode = $syntaxTree[9].Contents
            
            $orNode.Groups.Count | should be 3
            $orNode.Groups.Nodes.Count | should be 3
            ($orNode.Groups.Nodes | ? { $_ -is [ParameterNode] }).Count | should be 3
             
            $p = $orNode.Groups[0].Nodes[0]
            $paginated = $orNode.Groups[1].Nodes[0]
            $noPager = $orNode.Groups[2].Nodes[0]
            
            $p.Text | should be "-p"
            $paginated.Text | should be "--paginate"
            $noPager.Text | should be "--no-pager"
        }
        
        It "should have a -C parameter with a mandatory arg <path>" {
            $param = GetOptionalParameter "-C"
            
            $param -is [ParameterNode] | should be $true
            $param.Text | should be "-C"
            $param.ArgumentRequired | should be $true
            $param.ArgumentDelimiter | should be ""
            $param.Argument.ArgumentName | should be "path"
        }
        
        It "should have a --exec-path with an optional argument <path>" {
            $execPath = GetOptionalParameter "--exec-path"
            
            $execPath -is [ParameterNode] | should be $true
            $execPath.Text | should be "--exec-path"
            $execPath.ArgumentRequired | should be $false
            $execPath.ArgumentDelimiter | should be "="
            $execPath.Argument.ArgumentName | should be "path"
        }
        
        It "should have a --namespace param with a required, delimited argument <name>" {
            $namespace = GetOptionalParameter "--namespace"
            
            $namespace -is [ParameterNode] | should be $true
            $namespace.Text | should be "--namespace"
            $namespace.ArgumentRequired | should be $true
            $namespace.ArgumentDelimiter | should be "="
            $namespace.Argument.ArgumentName | should be "name"
        }
        
        It "should have an unbracketed <command> node" {
            $command = $syntaxTree | ? { $_.Text -eq "<command>"}
            
            $command -is [ArgumentNode] | should be $true
            $command.ArgumentName | should be "command"
        }
        
        It "should have a bracketed <args> node" {
            $args = $syntaxTree | 
                ? { $_ -is [BracketedNode] } | 
                ? { $_.Contents[0].Text -eq "<args>" }
            
            $args.Contents.Count | should be 1
            
            $args.Contents[0] -is [ArgumentNode] | should be $true
            $args.Contents.ArgumentName | should be "args"
        }
    }
}