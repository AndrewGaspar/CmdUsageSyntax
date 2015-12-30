
$windowsParameterSyntax = "(?<windows_parameter>/\w+)"
$shortParameterSwitchSyntax = "(?<short_parameter_switch>-\w+)"
$longParameterSwitchSyntax = "(?<long_parameter_switch>--\w[\w-]+)"
$parameterSwitchSyntax = "(?<parameter_switch>$shortParameterSwitchSyntax|$longParameterSwitchSyntax|$windowsParameterSyntax)"
$argumentNameSyntax = "(?<argument_name>\w[\w-\.\|]*)"
$argumentSyntax = "(?<argument>\<$argumentNameSyntax\>)"
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
    
    # don't need to capture white space characters, they just separate tokens
    # don't want to skip over capture of = and bracket characters, however
    # if(IsWhitespaceToken $text[$i]) {
    #     $updateCurrentIter++
    # }
}

function BuildSyntaxTree($text) {
    $context = New-Object SyntaxTreeBuilderContext -Property @{
        Text = $text
        CurrentTextIndex = 0
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
