# Docker Image Lineage Tracking
I am a Solutions Architect working on a large customer with a wide range of needs.  This customer has centralized their enterprise's Docker / OCI image regsitry on the JFrog Platform.  I am working on a solution to help the customer understand and trace the lineage of an image published to local Docker repositories in their JFrog Platform

## Customer Use-Case
 The customer has outlined a specific workflow for which they are requesting some assistance:


```
Seeking your technical advice. 

In the words of @JM and in the interest of @AK:
We are trying to understand whether Artifactory can help us preserve and expose provenance information for container images. Specifically, if an application team builds a new image and changes the image name, can we still determine the original base image through image metadata, OCI artifact metadata, build information, image layers, or other Artifactory capabilities?

That's very close to what Clifford was actually describing and avoids jumping immediately into a signing solution. The business capability you're really asking for is image lineage/provenance tracking, not necessarily image signing.


What capabilities does JFrog natively provide for this?  What could we layer on or develop additionally to achieve the goal of understanding images NOT built upon purchased “golden images”, but could / should have been?


Also, would this be a case for Compliant Version Selection or a subset of that?  Though, remember, it is primarily for DOCKER images in our current use case.
```

Another bit of insight from the customer identified as "@JM".  In the below statement, "EOL" refers to "End of Life", "ESRO" refers to the name of the customer's Application Security organization.  

```
I’m looking for non-golden image data and the ability to trace the original image information back to its upstream source within our environment. Shawn refers to this as lineage.

I will set up a call with Tom to discuss how JFrog can help us obtain the data needed to clearly understand which images are being used. Eventually, we may also need to determine whether any of those images are EOL or have not been refreshed within the timelines established by ESRO.

For now, the first step is to obtain the upstream image information currently being used.
```

In
## Jfrog Solution Architect Insight
My initial ideas here are around using the 'Build Info' resource as part of this solution.  Creating a Build-Info object from a Docker base image is probably going to be important, but research the details to make sure.

Also, I am only marginally literate in Docker image manifests, and how base images are tracked or recorded in that asset.  It's quite possible that there can be data and tracking information that can be used.

There are a variety of Jfrog REST API endpoints that can perhaps fetch data that would be used in this tracking & detection of a given image's "lineage"

### Details on Developer Experience of Selecting and Using a Golden Image
When asked about the process by which a Developer selects and uses  a Golden Image, this response was provided by the customer:
```
When a new application team needs to containerise an application and create a Dockerfile, the first step (ideally) is to determine which base image meets Acme security and compliance requirements.

The developer reviews the approved image catalogue (Navigator, Artifactory, or Golden Images documentation) to identify a supported image that matches the application requirements from one of the following locations:

FROM <registry domain>/<repo>/acmecorp-goldenimages/<Imagetype>:<tag>

repo: <project>-docker-vir [or] glb-docker-acmecorp-loc
registry domain: edgeinternal1acme.acme.com [or] centralacme.jfrog.io [or]  edgecore.acme.com

After selecting the image type, the team chooses the appropriate version/tag and incorporates it into the Dockerfile. At this point, the lineage chain begins because the application image inherits from the Golden Image. The CI/CD pipeline then builds the application image.

Once built, the image may be stored in Artifactory repositories, ACR, ECR, or other registries. Over time, users may no longer reference the original Acme repositories directly because they are working with their own derived images in their repos.

For Non-Golden Images

The users check for the availability of the image in docker hub/external public repos ..etc  and tries to pull from mirrored repo.
FROM <registry domain>/<mirror repo>/<Imagetype>:<tag>
```

It appears that there is internal documentation that guides the Developer which Golden Images are available to them, and the Golden Image is assumed to be already present in the Artifactory global local repository `acmecorp-goldenimages.

It is not clear what other identifying properties or metadata are present on the image once it's built and published into Artifactory

An entire engineering team is responsible for building and publishing these Golden Images.  Dev teams consume the output of the "Golden Images" team.  The Golden Images team builds and publishes their Golden images via Github Actions.  This team is decoupled from the large, diverse group of engineering teams that consume Golden Images.

A key scenario we will need to account for is a lineage chain that builds child images off child images over time.  Consider the following sequence of events, ignoring Dockerfile syntax issues.  The Dockerfile snippets are for illustrative purposes only.

1. Engineering Team "Alpha" builds an application image off Golden Image "Foo". This image is named "Bar", tagged `v0.1` . The Dockerfile for Bar:v0.1 would look like:

```dockerfile
FROM: acmecorp.jfrog.io/acmecorp-goldenimages/Foo:SHA123456
ENTRYPOINT: run.sh
```

2. Some time later, a new application image is created by team "Alpha", only this time it's built off `Bar:v0.1`.  This new application image is `Fizz` with tag `v0.1`.  The Dockerfile would look something like this:

```dockerfile
FROM: acmecorp.jfrog.io/alpha-local/Bar:v0.1
ENTRYPOINT: run.sh
```
Any proposed solution will sill need to accomodate validating that the original, root of the image lineage comes from a golden image.

## Docuemation Resource
Review the top-level documentation at https://docs.jfrog.com.  Pay specific attention to docuemtnation on Docker repositories, XRay Docker scans, producing SBOMS for Docker images with JFrog XRay, attaching software provenance, called "Evidence" in the JFrog portfolio and specific APIs and CLI Commands that might support this use-case.

Also consider Docker and OCI image format documentation to determine what information is available in various Docker CLI commands and image manifests that can be used to support this use case.

## Local Experimentation
As part of researching this use-case there will likely be some local testing and validation that needs to be done.  I have Rancher Desktop installed and running for a Docker engine.  I have a JFrog CLI instance connected to a JFrog Platform Deployment ("JPD") located at `https://tomjpd2.jfrog.io`.  We may need to build some example Dockerfiles, build those images, deploy into my JPD and make API or CLI calls into my platform to verify this use-case.

