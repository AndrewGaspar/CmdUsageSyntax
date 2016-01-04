
$windowsParameterSyntax = "(?<windows_parameter>/\w+)"
$shortParameterSwitchSyntax = "(?<short_parameter_switch>-\w+)"
$longParameterSwitchSyntax = "(?<long_parameter_switch>--\w[\w-]+)"
$parameterSwitchSyntax = "(?<parameter_switch>$shortParameterSwitchSyntax|$longParameterSwitchSyntax|$windowsParameterSyntax)"
$argumentNameSyntax = "(?<argument_name>\w[\w-\.\|]*)"

$argumentSyntax = "(?<argument>\<$argumentNameSyntax\>)"
# $manyArgumentSyntax = "(?<first_argument>$argumentSyntax)(?: \| (?<rest_arguments>(?:$argumentSyntax \| )*$argumentSyntax))?"

$assignmentArgumentSyntax = "(?<assignment_argument>(?<argument_delimiter>=)$argumentSyntax)"
$windowsAssignmentArgumentSyntax = "(?<windows_assignment_argument>\:$argumentNameSyntax)"
$explicitSeparationSyntax = "--"

$usageSyntax = "(?<command_name>\w[\w-\._]*)"

class EnclosedTextResults {
    [string]$InternalText
    [string]$RemainingText
}

function IndexOfClosingBracket($openingBracket, $closingBracket, $text, $subStringIndex = 0) {
    if($text[$subStringIndex] -ne $openingBracket) {
        return $subStringIndex - 1
    }
    
    for($i = $subStringIndex + 1; $i -lt $text.Length; $i++) {
        if($text[$i] -eq $openingBracket) {
            $result = IndexOfClosingBracket $openingBracket $closingBracket $text $i
            if($result.IsUnbalanced) {
                $result.Depth++
                return $result
            }
            $i = $result
        } elseif ($text[$i] -eq $closingBracket) {
            return $i
        }
    }
    
    return New-Object PSObject -Property @{
        IsUnbalanced = $true
        Depth = 1
    }
}

class Node {
    [string]$Text
}

class TextNode : Node { }

class ParameterNode : Node {
    [ArgumentNode]$Argument
    [bool]$ArgumentRequired
    [string]$ArgumentDelimiter
}

class ArgumentNode : Node {
    [string]$ArgumentName
}

class BracketedNode : Node {
    [string]$EnclosedText
    [string]$OpenBracket
    [string]$CloseBracket
    [Node[]]$Contents
}

class GroupedNode : Node {
    [Node[]]$Nodes
}

class OrNode : Node {
    [Node[]]$Groups
}

function IsEndOfToken($character) {
    return (IsWhitespaceToken $character) -or `
        (IsOpenBracketToken($character)) -or `
        ($character -match "[=\:]")
}

function IsWhitespaceToken($character) {
    return $character -match '\s'
}

function IsOpenBracketToken($character) {
    return $character -match '[\{\[\(]'
}

function IsCloseBracketToken($character) {
    return $character -match '[\}\]\)]'
}

function GetCloseBracket($character) {
    if($character -eq '{') {
        return '}'
    }
    
    if($character -eq '(') {
        return ')'
    }
    
    if($character -eq '[') {
        return ']'
    }
}

class SyntaxTreeBuilderContext {
    [int]$CurrentTextIndex
    [string]$Text
    [ParameterNode]$CurrentParameter
    [OrNode]$LeftOperand
}


function TryHandleParameterArgumentNode([SyntaxTreeBuilderContext]$context, [Node]$node) {
    if($null -eq $context.CurrentParameter) {
        return $false
    }
    
    if($node -is [TextNode]) {
        if($node.Text -match "^$argumentSyntax$" -or `
            $node.Text -match "^$assignmentArgumentSyntax$") {
            $context.CurrentParameter.Argument = New-Object ArgumentNode -Property @{
                Text = $node.Text
                ArgumentName = $Matches["argument_name"]
            }
            
            $context.CurrentParameter.ArgumentRequired = $True
            $context.CurrentParameter.ArgumentDelimiter = $Matches["argument_delimiter"]
            
            return $true
        }
    }
    
    if(($node -is [BracketedNode]) -and `
        ($node.OpenBracket -eq '[') -and `
        ($node.Contents.Count -eq 1) -and `
        ($node.Contents[0] -is [TextNode])) {
            
        $textNode = [TextNode]$node.Contents[0]
            
        if($textNode.Text -match "^$assignmentArgumentSyntax$") {
            $context.CurrentParameter.Argument = New-Object ArgumentNode -Property @{
                Text = $textNode.Text
                ArgumentName = $Matches["argument_name"]
            }
            
            $context.CurrentParameter.ArgumentRequired = $false
            $context.CurrentParameter.ArgumentDelimiter = $Matches["argument_delimiter"]
            
            return $true
        }
    }
    
    return $false
}

function HandleNewNode([SyntaxTreeBuilderContext]$context, [Node]$node) {
    #handle context of a parameter needing argument
    if($null -ne $context.CurrentParameter) {
        $isArgument = TryHandleParameterArgumentNode $context $node
        
        $context.CurrentParameter
        $context.CurrentParameter = $null
        
        if($isArgument) {
            # the node has been bound to the last parameter node, so don't allow anybody else to process it
            $node = $null
        }
    } 
    
    if($node -is [TextNode]) {
        $token = $node.Text
        
        # check if it is a free-floating argument
        if($token -match "^$argumentSyntax$") {
            New-Object ArgumentNode -Property @{
                Text = $token
                ArgumentName = $Matches["argument_name"]
            }
            
            $node = $null
        } elseif($token -match "^$parameterSwitchSyntax$") {
            $context.CurrentParameter = New-Object ParameterNode -Property @{
                Text = $token
            }
            
            $node = $null
        }
    }
    
    if($node) {
        $node
        $node = $null
    }
}

function SplitOnOrOperators([string]$text) {
    & {
        $lastElement = 0
        for($i = 0; $i -lt $text.Length; $i++) {
            if(IsOpenBracketToken $text[$i]) {
                $openBracket = $text[$i]
                $closeBracket = GetCloseBracket $text[$i]
                
                $i = IndexOfClosingBracket $openBracket $closeBracket $text $i
            } elseif('|' -eq $text[$i]) {
                $text.Substring($lastElement, $i - $lastElement).Trim()
                $lastElement = $i + 1
            }
        }

        $text.Substring($lastElement, $i - $lastElement).Trim()
    } | Where-Object { $_ }
}

function BuildSyntaxTree($text) {
    $context = New-Object SyntaxTreeBuilderContext -Property @{
        Text = $text
        CurrentTextIndex = 0
    }
    
    $elements = SplitOnOrOperators $text
    if($elements.Count -gt 1) {
        return New-Object OrNode -Property @{
            Text = $text
            Groups = [GroupedNode[]]($elements | % { 
                New-Object GroupedNode -Property @{
                    Text = $_
                    Nodes = [Node[]](BuildSyntaxTree $_)
                } })
        }
    }
    
    for($i = 0; $i -le $text.Length; $i++) {
        $updateCurrentIter = $context.CurrentTextIndex
        
        if(($i -eq $text.Length) -or (IsEndOfToken $text[$i])) {
            $token = $text.Substring($context.CurrentTextIndex, $i - $context.CurrentTextIndex)
            
            if($token.Length -gt 0)
            {
                HandleNewNode $context (New-Object TextNode -Property @{
                    Text = $token
                })
            }
            
            $updateCurrentIter = $i
        }
        
        if(IsOpenBracketToken $text[$i]) {
            $openBracket = $text[$i]
            $closeBracket = GetCloseBracket $text[$i]
            
            $cbIndex = IndexOfClosingBracket $openBracket $closeBracket $text $i
            
            $bracketingText = $text.Substring($i, $cbIndex + 1 - $i)
            $bracketedText = $bracketingText.Substring(1, $bracketingText.Length - 2)
            
            $nodes = BuildSyntaxTree $bracketedText
            
            HandleNewNode $context (New-Object BracketedNode -Property @{
                Text = $bracketingText
                EnclosedText = $bracketedText
                OpenBracket = $openBracket
                CloseBracket = $closeBracket
                Contents = [Node[]]$nodes
            })
            
            $i = $cbIndex
            $updateCurrentIter = $i + 1
        }
        
        if(IsWhitespaceToken $text[$i]) {
            $updateCurrentIter++
        }
        
        $context.CurrentTextIndex = $updateCurrentIter
    }
    
    if($context.CurrentParameter) {
        $context.CurrentParameter
    }
}

function New-CmdUsageSyntaxNode {
    Param(
        [Parameter(ValueFromPipeline=$True)]
        [string]$Usage
    )
    
    process { BuildSyntaxTree $Usage }
}

class UsageElement {
    [bool]$IsOptional = $false
    [string]ToString() { 
        $result = $this.InternalToString()
        
        if($this.IsOptional) {
            return "[$result]"
        } else {
            return $result
        }
    }
}

class ArgumentUsage : UsageElement {
    [string]$Name
    [string]$Delimiter
    
    [string]InternalToString() {
        return "$($this.Delimiter)<$($this.Name)>"
    }
}

class ParameterUsage : UsageElement {
    [string]$Parameter
    [ArgumentUsage]$Argument
    
    [bool]IsSwitch() {
        return $null -eq $this.Argument
    }
    
    [string]InternalToString() {
        
        if($this.IsSwitch()) {
            return $this.Parameter
        } else {
            return "$($this.Parameter)$($this.Argument)"
        }
    }
}

class SetUsage : UsageElement {
    [UsageElement[]]$Elements
}

class CommandUsage : SetUsage {
    [string]$Command
    
    [string]InternalToString() {
        return (& {
            $this.Command
            
            $this.Elements
        } | where { $_ }) -join " "
    }
}

class GroupedSetUsage : SetUsage {
    [string]InternalToString() {
        return $this.Elements -join " "
    }
}

class OrSetUsage : SetUsage {
    [string]InternalToString() {
        return $this.Elements -Join " | "
    }
    
    [string]ToString() {
        if($this.IsOptional) {
            return "[$($this.InternalToString())]"
        } else {
            return "($($this.InternalToString()))"
        }
    }
}

function Format-CmdUsageSyntax {
    $nodes = $input | % { $_ }
    
    for($i = 0; $i -lt $nodes.Count; $i++) {
        $node = $nodes[$i]
    
        if($node -is [TextNode]) {
            return New-Object CommandUsage -Property @{
                Command = $node.Text
                Elements = [UsageElement[]]($nodes | select -skip ($i+1) | Format-CmdUsageSyntax)
            }
        } elseif($node -is [ParameterNode]) {
            $parameter = New-Object ParameterUsage -Property @{
                Parameter = $node.Text
            }
            
            if($node.Argument) {
                $parameter.Argument = New-Object ArgumentUsage -Property @{
                    Name = $node.Argument.ArgumentName
                    IsOptional = !$node.ArgumentRequired
                }
                
                if($node.ArgumentDelimiter) {
                    $parameter.Argument.Delimiter = $node.ArgumentDelimiter
                } else {
                    $parameter.Argument.Delimiter = " "
                }
            }
            
            $parameter
        } elseif($node -is [ArgumentNode]) {
            New-Object ArgumentUsage -Property @{
                Name = $node.ArgumentName
            }
        } elseif($node -is [BracketedNode]) {
            if($node.Contents.Count -eq 1) {
                $usage = $node.Contents[0] | Format-CmdUsageSyntax
            } else {
                $usage = New-Object GroupedSetUsage -Property @{
                    Elements = [UsageElement[]]($node.Contents | Format-CmdUsageSyntax)
                }
            }
            if($usage) {
                if($node.OpenBracket -eq '[') {
                    $usage.IsOptional = $true
                }
                $usage
            }
        } elseif($node -is [OrNode]) {
            New-Object OrSetUsage -Property @{
                Elements = [UsageElement[]]($node.Groups | ForEach-Object {
                    New-Object GroupedSetUsage -Property @{
                        Elements = [UsageElement[]]($_.Nodes | Format-CmdUsageSyntax)
                    }
                })
            }
        }
    }
}
