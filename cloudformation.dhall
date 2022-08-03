let hostedZone =
      \(domainName : Text) ->
        { Type = "AWS::Route53::HostedZone", Properties.Name = domainName }

let cert =
      \(hostedZoneLogicalId : Text) ->
      \(domainName : Text) ->
        { Type = "AWS::CertificateManager::Certificate"
        , Properties =
          { DomainName = domainName
          , DomainValidationOptions =
            [ { DomainName = domainName
              , HostedZoneId =
                [ { mapKey = "Ref", mapValue = hostedZoneLogicalId } ]
              }
            ]
          , ValidationMethod = "DNS"
          }
        }

let bucket = { Type = "AWS::S3::Bucket", Properties = {=} }

let bucketPolicy =
      \(bucketLogicalId : Text) ->
      \(originAccessIdentityLogicalId : Text) ->
        { Type = "AWS::S3::BucketPolicy"
        , Properties =
          { Bucket = [ { mapKey = "Ref", mapValue = bucketLogicalId } ]
          , PolicyDocument =
            { Version = "2012-10-17"
            , Statement =
              [ { Action = [ "s3:GetObject" ]
                , Effect = "Allow"
                , Resource =
                  [ { mapKey = "Fn::Sub"
                    , mapValue = "\${${bucketLogicalId}}/*"
                    }
                  ]
                , Principal.CanonicalUser
                  =
                  [ { mapKey = "Fn::GetAtt"
                    , mapValue =
                      [ originAccessIdentityLogicalId, "S3CanonicalUserId" ]
                    }
                  ]
                }
              ]
            }
          }
        }

let oai =
      \(domainName : Text) ->
        { Type = "AWS::CloudFront::CloudFrontOriginAccessIdentity"
        , Properties.CloudFrontOriginAccessIdentityConfig.Comment
          = "For ${domainName}"
        }

let distro =
      \(originAccessIdentityLogicalId : Text) ->
      \(certificateLogicalId : Text) ->
      \(bucketLogicalId : Text) ->
      \(domainName : Text) ->
        let originId = "myS3Origin"

        in  { Type = "AWS::CloudFront::Distribution"
            , Properties.DistributionConfig
              =
              { Origins =
                [ { DomainName =
                    [ { mapKey = "Fn::GetAtt"
                      , mapValue = [ bucketLogicalId, "DomainName" ]
                      }
                    ]
                  , Id = originId
                  , S3OriginConfig.OriginAccessIdentity
                    =
                    [ { mapKey = "Fn::Sub"
                      , mapValue =
                          "origin-access-identity/cloudfront/\${${originAccessIdentityLogicalId}}"
                      }
                    ]
                  }
                ]
              , Enabled = "true"
              , Comment = "Some comment"
              , DefaultRootObject = "index.html"
              , Aliases = [ domainName ]
              , DefaultCacheBehavior =
                { AllowedMethods = [ "GET", "HEAD", "OPTIONS" ]
                , TargetOriginId = originId
                , ForwardedValues =
                  { QueryString = "false", Cookies.Forward = "none" }
                , ViewerProtocolPolicy = "redirect-to-https"
                }
              , HttpVersion = "http2"
              , PriceClass = "PriceClass_200"
              , ViewerCertificate =
                { AcmCertificateArn =
                  [ { mapKey = "Ref", mapValue = certificateLogicalId } ]
                , MinimumProtocolVersion = "TLSv1.2_2021"
                , SslSupportMethod = "sni-only"
                }
              }
            }

in  \(domainName : Text) ->
      { AWSTemplateFormatVersion = "2010-09-09"
      , Resources =
        { Distribution =
            distro "OriginAccessIdentity" "Certificate" "Bucket" domainName
        , HostedZone = hostedZone domainName
        , Bucket = bucket
        , BucketPolicy = bucketPolicy "Bucket" "OriginAccessIdentity"
        , OriginAccessIdentity = oai domainName
        , Certificate = cert "HostedZone" domainName
        }
      }